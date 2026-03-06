(* Nostr channel via NIP-17 gift-wrap events using the nak CLI tool *)

(* LRU-1000 dedup by event ID *)
let dedup_set : (string, unit) Hashtbl.t = Hashtbl.create 1024
let dedup_queue : string Queue.t = Queue.create ()
let dedup_max = 1000

let dedup_seen id =
  if Hashtbl.mem dedup_set id then true
  else begin
    if Queue.length dedup_queue >= dedup_max then begin
      let oldest = Queue.pop dedup_queue in
      Hashtbl.remove dedup_set oldest
    end;
    Queue.push id dedup_queue;
    Hashtbl.add dedup_set id ();
    false
  end

let is_allowed ~(config : Runtime_config.nostr_config) ~pubkey =
  match config.allow_from with [ "*" ] -> true | ids -> List.mem pubkey ids

(* Send a DM via nak dm *)
let send_dm ~(config : Runtime_config.nostr_config) ~recipient ~content =
  let open Lwt.Syntax in
  let relay_args = config.relays in
  let args =
    Array.of_list
      ([
         config.nak_path; "dm"; "--sec"; config.private_key; recipient; content;
       ]
      @ relay_args)
  in
  let cmd = (config.nak_path, args) in
  Lwt.catch
    (fun () ->
      let proc = Lwt_process.open_process_none cmd in
      let* status = proc#status in
      (match status with
      | Unix.WEXITED 0 -> ()
      | Unix.WEXITED n ->
          Logs.warn (fun m -> m "Nostr: nak dm exited with code %d" n)
      | _ -> Logs.warn (fun m -> m "Nostr: nak dm terminated abnormally"));
      Lwt.return_unit)
    (fun exn ->
      Logs.err (fun m ->
          m "Nostr: failed to send DM: %s" (Printexc.to_string exn));
      Lwt.return_unit)

(* Parse a NIP-17 gift-wrap event line from nak output.
   Returns (event_id, sender_pubkey, content) option *)
let parse_event_line line =
  try
    let json = Yojson.Safe.from_string line in
    let open Yojson.Safe.Util in
    let id = json |> member "id" |> to_string in
    (* kind 1059 is gift-wrap; inner content is the rumor *)
    let content = try json |> member "content" |> to_string with _ -> "" in
    (* pubkey is the sender of the gift-wrap (may be ephemeral) *)
    let pubkey = try json |> member "pubkey" |> to_string with _ -> "" in
    (* Try to get the actual sender from the inner decrypted content *)
    let actual_sender, text =
      try
        let inner = Yojson.Safe.from_string content in
        let sender = inner |> member "pubkey" |> to_string in
        let msg =
          try inner |> member "content" |> to_string with _ -> content
        in
        (sender, msg)
      with _ -> (pubkey, content)
    in
    if id = "" || text = "" then None else Some (id, actual_sender, text)
  with _ -> None

let listen_relay ~(config : Runtime_config.nostr_config) relay
    ~(session_mgr : Session.t) =
  let open Lwt.Syntax in
  let args =
    Array.of_list
      [
        config.nak_path;
        "req";
        "-k";
        "1059";
        "--sec";
        config.private_key;
        "--dm";
        config.pubkey;
        relay;
      ]
  in
  let cmd = (config.nak_path, args) in
  Lwt.catch
    (fun () ->
      let proc = Lwt_process.open_process_in cmd in
      let rec read_loop () =
        let* line_opt =
          Lwt.catch
            (fun () ->
              let* line = Lwt_io.read_line proc#stdout in
              Lwt.return (Some line))
            (fun _ -> Lwt.return None)
        in
        match line_opt with
        | None -> Lwt.return_unit
        | Some line ->
            let* () =
              match parse_event_line line with
              | None -> Lwt.return_unit
              | Some (id, sender, text) -> (
                  if dedup_seen id then Lwt.return_unit
                  else if not (is_allowed ~config ~pubkey:sender) then begin
                    Logs.warn (fun m ->
                        m "Nostr: ignoring message from unauthorized pubkey=%s"
                          sender);
                    Lwt.return_unit
                  end
                  else
                    let key = "nostr:" ^ sender in
                    let* result =
                      Lwt.catch
                        (fun () ->
                          let* response =
                            Session.turn session_mgr ~key ~message:text
                              ~channel_name:"nostr" ~channel_type:"dm" ()
                          in
                          Lwt.return (Ok response))
                        (fun exn -> Lwt.return (Error (Printexc.to_string exn)))
                    in
                    match result with
                    | Ok response ->
                        send_dm ~config ~recipient:sender ~content:response
                    | Error err ->
                        Logs.err (fun m ->
                            m "Nostr: agent error for pubkey=%s: %s" sender err);
                        Lwt.return_unit)
            in
            read_loop ()
      in
      read_loop ())
    (fun exn ->
      Logs.err (fun m ->
          m "Nostr: listen_relay error on %s: %s" relay (Printexc.to_string exn));
      Lwt.return_unit)

let start ~(config : Runtime_config.t) ~(session_manager : Session.t) =
  match config.channels.nostr with
  | None ->
      Logs.info (fun m -> m "No Nostr config found, skipping");
      Lwt.return_unit
  | Some nostr_config ->
      if nostr_config.private_key = "" then begin
        Logs.warn (fun m -> m "Nostr: private_key is empty, skipping");
        Lwt.return_unit
      end
      else if nostr_config.relays = [] then begin
        Logs.warn (fun m -> m "Nostr: no relays configured, skipping");
        Lwt.return_unit
      end
      else begin
        Logs.info (fun m ->
            m "Nostr channel starting (nak=%s, relays=%d)" nostr_config.nak_path
              (List.length nostr_config.relays));
        (* Listen on all relays in parallel *)
        let loops =
          List.map
            (fun relay ->
              let open Lwt.Syntax in
              let backoff = ref 1.0 in
              let rec reconnect () =
                let t0 = Unix.gettimeofday () in
                let* () =
                  listen_relay ~config:nostr_config relay
                    ~session_mgr:session_manager
                in
                let elapsed = Unix.gettimeofday () -. t0 in
                if elapsed > 30.0 then backoff := 1.0;
                let delay = !backoff in
                backoff := Float.min (!backoff *. 2.0) 60.0;
                Logs.info (fun m ->
                    m "Nostr: relay %s disconnected, reconnecting in %.0fs"
                      relay delay);
                let* () = Lwt_unix.sleep delay in
                reconnect ()
              in
              reconnect ())
            nostr_config.relays
        in
        Lwt.join loops
      end
