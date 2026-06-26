(* Force-link provider_init.ml so its native-provider registrations run. *)
let _link_provider_init = Provider_init.registered
let get_config () = Config_loader.load ()
let daemon_state_path () = Dot_dir.sub "daemon_state.json"

let remove_daemon_state () =
  let path = daemon_state_path () in
  if Sys.file_exists path then try Sys.remove path with _ -> ()

let pid_is_alive pid =
  try
    Unix.kill pid 0;
    true
  with Unix.Unix_error _ -> false

let read_file path =
  try
    let ic = open_in path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr ic)
      (fun () ->
        let s = really_input_string ic (in_channel_length ic) in
        Some s)
  with _ -> None

let proc_start_ticks pid =
  let path = Printf.sprintf "/proc/%d/stat" pid in
  match read_file path with
  | None -> None
  | Some stat -> (
      let idx = try Some (String.rindex stat ')') with _ -> None in
      match idx with
      | None -> None
      | Some i -> (
          let rest = String.sub stat (i + 2) (String.length stat - i - 2) in
          let fields =
            String.split_on_char ' ' rest |> List.filter (fun s -> s <> "")
          in
          try Some (List.nth fields 19) with _ -> None))

let proc_cmdline_contains ~needle pid =
  let path = Printf.sprintf "/proc/%d/cmdline" pid in
  match read_file path with
  | None -> false
  | Some s ->
      let hay = String.lowercase_ascii s in
      let nee = String.lowercase_ascii needle in
      let hlen = String.length hay in
      let nlen = String.length nee in
      let rec loop i =
        if i + nlen > hlen then false
        else if String.sub hay i nlen = nee then true
        else loop (i + 1)
      in
      nlen > 0 && loop 0

let read_daemon_state () =
  let path = daemon_state_path () in
  if Sys.file_exists path then
    try
      let json = Yojson.Safe.from_file path in
      Some json
    with _ -> None
  else None

let gateway_token_path () = Dot_dir.sub "gateway_token"

let read_gateway_token () =
  match read_file (gateway_token_path ()) with
  | Some token when String.trim token <> "" -> Some (String.trim token)
  | _ -> None

let save_gateway_token token =
  let token = String.trim token in
  let clawq_dir = Dot_dir.path () in
  (try if not (Sys.file_exists clawq_dir) then Sys.mkdir clawq_dir 0o700
   with _ -> ());
  let token_path = gateway_token_path () in
  let fd =
    Unix.openfile token_path [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o600
  in
  let oc = Unix.out_channel_of_descr fd in
  Fun.protect
    (fun () -> output_string oc token)
    ~finally:(fun () -> close_out oc)

let read_live_daemon_gateway () =
  match read_daemon_state () with
  | None -> None
  | Some json -> (
      let open Yojson.Safe.Util in
      try
        let pid = json |> member "pid" |> to_int in
        if not (pid_is_alive pid) then begin
          remove_daemon_state ();
          None
        end
        else
          Some
            ( json |> member "gateway_host" |> to_string,
              json |> member "gateway_port" |> to_int )
      with _ -> None)

let read_daemon_tunnel_info () =
  match read_daemon_state () with
  | None -> None
  | Some json -> (
      let open Yojson.Safe.Util in
      try
        let pid = json |> member "pid" |> to_int in
        if not (pid_is_alive pid) then begin
          remove_daemon_state ();
          None
        end
        else
          match json |> member "tunnel" with
          | `Null -> None
          | tunnel_json ->
              let state = tunnel_json |> member "state" |> to_string in
              if state = "active" then
                let provider =
                  try tunnel_json |> member "provider" |> to_string
                  with _ -> "unknown"
                in
                let url =
                  match tunnel_json |> member "url" with
                  | `String u -> Some u
                  | _ -> None
                in
                Some (provider, url)
              else None
      with _ -> None)

let get_sync ~uri ~headers =
  Lwt_main.run
    (Lwt.catch
       (fun () ->
         let open Lwt.Syntax in
         let* status, resp_body = Http_client.get ~uri ~headers in
         Lwt.return (Ok (status, resp_body)))
       (fun exn -> Lwt.return (Error (Printexc.to_string exn))))

let try_localhost_gateway () =
  (* Try to detect a gateway running on localhost without requiring daemon_state.json *)
  let host = "127.0.0.1" in
  let port = 13451 in
  let url = Printf.sprintf "http://%s:%d/health" host port in
  match get_sync ~uri:url ~headers:[] with
  | Error _ -> None
  | Ok (200, _) -> Some (host, port)
  | Ok _ -> None

let gateway_auth_headers cfg =
  match (cfg.Runtime_config.gateway.auth_token, read_gateway_token ()) with
  | Some token, _ when String.trim token <> "" ->
      [ ("Authorization", "Bearer " ^ String.trim token) ]
  | None, Some token -> [ ("Authorization", "Bearer " ^ token) ]
  | _ -> []

let parse_json_error_body body =
  try
    let json = Yojson.Safe.from_string body in
    match Yojson.Safe.Util.member "error" json with
    | `String msg -> Some msg
    | _ -> None
  with _ -> None

let is_loopback_host = String_util.is_loopback_host

let post_json_sync ~uri ~headers ~body =
  Lwt_main.run
    (Lwt.catch
       (fun () ->
         let open Lwt.Syntax in
         let* status, resp_body = Http_client.post_json ~uri ~headers ~body in
         Lwt.return (Ok (status, resp_body)))
       (fun exn -> Lwt.return (Error (Printexc.to_string exn))))

let read_live_gateway_pairing_code () =
  match read_daemon_state () with
  | None -> None
  | Some json -> (
      let open Yojson.Safe.Util in
      try
        let pid = json |> member "pid" |> to_int in
        if pid_is_alive pid then
          match json |> member "pairing_code" with
          | `String code when code <> "" -> Some code
          | _ -> None
        else begin
          remove_daemon_state ();
          None
        end
      with _ -> None)

type auto_pair_result = No_attempt | Paired of string | Pair_failed of string

let fetch_gateway_pairing_code ~host ~port =
  (* Fetch the pairing code directly from the running gateway via GET /pair.
     Only safe because this path is guarded by is_loopback_host. *)
  let url = Printf.sprintf "http://%s:%d/pair" host port in
  match get_sync ~uri:url ~headers:[] with
  | Error _ -> None
  | Ok (200, body) -> (
      try
        let json = Yojson.Safe.from_string body in
        let open Yojson.Safe.Util in
        match json |> member "code" with
        | `String code when String.trim code <> "" -> Some (String.trim code)
        | _ -> None
      with _ -> None)
  | Ok _ -> None

let try_auto_pair_live_gateway ~host ~port =
  if not (is_loopback_host host) then No_attempt
  else
    let code =
      match read_live_gateway_pairing_code () with
      | Some _ as c -> c
      | None -> fetch_gateway_pairing_code ~host ~port
    in
    match code with
    | None -> No_attempt
    | Some code -> (
        let url = Printf.sprintf "http://%s:%d/pair" host port in
        let body = `Assoc [ ("code", `String code) ] |> Yojson.Safe.to_string in
        match post_json_sync ~uri:url ~headers:[] ~body with
        | Error msg -> Pair_failed ("pairing request failed: " ^ msg)
        | Ok (status, resp_body) -> (
            match status with
            | 200 -> (
                try
                  let json = Yojson.Safe.from_string resp_body in
                  let open Yojson.Safe.Util in
                  match json |> member "token" with
                  | `String token when String.trim token <> "" ->
                      save_gateway_token token;
                      Paired (String.trim token)
                  | _ ->
                      Pair_failed
                        "pairing response did not contain a usable token"
                with exn ->
                  Pair_failed
                    (Printf.sprintf "failed to parse pairing response: %s"
                       (Printexc.to_string exn)))
            | _ ->
                Pair_failed
                  (match parse_json_error_body resp_body with
                  | Some msg -> msg
                  | None -> resp_body)))

let post_live_gateway_json ~cfg ~host ~port ~path ~body =
  let url = Printf.sprintf "http://%s:%d%s" host port path in
  let headers = gateway_auth_headers cfg in
  match post_json_sync ~uri:url ~headers ~body with
  | Ok ((401 | 403), _) as rejected -> (
      match try_auto_pair_live_gateway ~host ~port with
      | Paired token ->
          let retry_headers = [ ("Authorization", "Bearer " ^ token) ] in
          post_json_sync ~uri:url ~headers:retry_headers ~body
      | No_attempt -> rejected
      | Pair_failed msg -> Error ("Auto-pair failed: " ^ msg))
  | other -> other

let get_db () =
  let cfg = get_config () in
  let db_path =
    if cfg.memory.db_path <> "" then cfg.memory.db_path else Dot_dir.db_path ()
  in
  let clawq_dir = Dot_dir.path () in
  (try if not (Sys.file_exists clawq_dir) then Sys.mkdir clawq_dir 0o755
   with _ -> ());
  Memory.init ~db_path ~search_enabled:cfg.memory.search_enabled ()
