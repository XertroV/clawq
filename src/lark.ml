(* Lark/Feishu channel *)

let feishu_base = "https://open.feishu.cn/open-apis"
let lark_base = "https://open.larksuite.com/open-apis"

let api_base (endpoint : string) =
  if endpoint = "lark" then lark_base else feishu_base

(* Tenant access token cache *)
let token_cache : (string * float) option ref = ref None

let get_tenant_access_token ~(config : Runtime_config.lark_config) =
  let open Lwt.Syntax in
  let now = Unix.gettimeofday () in
  match !token_cache with
  | Some (token, expiry) when now < expiry -> Lwt.return (Some token)
  | _ ->
      let base = api_base config.endpoint in
      let uri = base ^ "/auth/v3/tenant_access_token/internal" in
      let body =
        `Assoc
          [
            ("app_id", `String config.app_id);
            ("app_secret", `String config.app_secret);
          ]
        |> Yojson.Safe.to_string
      in
      let* status, resp_body = Http_client.post_json ~uri ~headers:[] ~body in
      if status >= 200 && status < 300 then (
        try
          let json = Yojson.Safe.from_string resp_body in
          let open Yojson.Safe.Util in
          let token = json |> member "tenant_access_token" |> to_string in
          let expire = try json |> member "expire" |> to_int with _ -> 7200 in
          (* Cache with 60s safety margin *)
          let expiry = now +. float_of_int expire -. 60.0 in
          token_cache := Some (token, expiry);
          Lwt.return (Some token)
        with exn ->
          Logs.err (fun m ->
              m "Lark: failed to parse token response: %s"
                (Printexc.to_string exn));
          Lwt.return None)
      else begin
        Logs.warn (fun m -> m "Lark: token fetch failed (HTTP %d)" status);
        Lwt.return None
      end

let is_allowed ~(config : Runtime_config.lark_config) ~user_id =
  match config.allow_users with [ "*" ] -> true | ids -> List.mem user_id ids

(* Verify Lark webhook signature: HMAC-SHA256 of timestamp + nonce + body *)
let verify_lark_signature ~verification_token ~timestamp ~nonce ~body ~signature
    =
  let payload = timestamp ^ nonce ^ body in
  let computed =
    Digestif.SHA256.hmac_string ~key:verification_token payload
    |> Digestif.SHA256.to_hex
  in
  Eqaf.equal computed signature

let send_message ~(config : Runtime_config.lark_config) ~chat_id ~text =
  let open Lwt.Syntax in
  let* token_opt = get_tenant_access_token ~config in
  match token_opt with
  | None ->
      Logs.err (fun m -> m "Lark: cannot send message, no token");
      Lwt.return_unit
  | Some token ->
      let base = api_base config.endpoint in
      let uri = base ^ "/im/v1/messages?receive_id_type=chat_id" in
      let headers = [ ("Authorization", "Bearer " ^ token) ] in
      let body =
        `Assoc
          [
            ("receive_id", `String chat_id);
            ("msg_type", `String "text");
            ( "content",
              `String
                (Yojson.Safe.to_string (`Assoc [ ("text", `String text) ])) );
          ]
        |> Yojson.Safe.to_string
      in
      let* _status, _body = Http_client.post_json ~uri ~headers ~body in
      Lwt.return_unit

let parse_message_event json =
  try
    let open Yojson.Safe.Util in
    let event = json |> member "event" in
    let message = event |> member "message" in
    let sender = event |> member "sender" in
    let chat_id = message |> member "chat_id" |> to_string in
    let user_id =
      try sender |> member "sender_id" |> member "open_id" |> to_string
      with _ -> ""
    in
    let text =
      try
        let content_str = message |> member "content" |> to_string in
        let content = Yojson.Safe.from_string content_str in
        content |> member "text" |> to_string
      with _ -> ""
    in
    let event_id =
      try json |> member "header" |> member "event_id" |> to_string
      with _ -> ""
    in
    if text = "" || chat_id = "" then None
    else Some (event_id, chat_id, user_id, text)
  with _ -> None

let handle_webhook_body ~(config : Runtime_config.lark_config)
    ~(session_mgr : Session.t) body_str =
  let open Lwt.Syntax in
  try
    let json = Yojson.Safe.from_string body_str in
    let open Yojson.Safe.Util in
    (* Challenge verification (URL verification) *)
    let challenge =
      try Some (json |> member "challenge" |> to_string) with _ -> None
    in
    match challenge with
    | Some ch ->
        let resp =
          `Assoc [ ("challenge", `String ch) ] |> Yojson.Safe.to_string
        in
        Lwt.return (`Challenge resp)
    | None -> (
        match parse_message_event json with
        | None -> Lwt.return (`Ok {|{"code":0}|})
        | Some (_event_id, chat_id, user_id, text) -> (
            if not (is_allowed ~config ~user_id) then (
              Logs.warn (fun m ->
                  m "Lark: ignoring message from unauthorized user=%s" user_id);
              Lwt.return (`Ok {|{"code":0}|}))
            else
              let key = "lark:" ^ chat_id ^ ":" ^ user_id in
              let* result =
                Lwt.catch
                  (fun () ->
                    let* response =
                      Session.turn session_mgr ~key ~message:text
                        ~channel_name:"lark" ~channel_type:"group"
                        ~sender_id:user_id ()
                    in
                    Lwt.return (Ok response))
                  (fun exn -> Lwt.return (Error (Printexc.to_string exn)))
              in
              match result with
              | Ok response ->
                  let* () = send_message ~config ~chat_id ~text:response in
                  Lwt.return (`Ok {|{"code":0}|})
              | Error err ->
                  Logs.err (fun m ->
                      m "Lark: agent error for chat=%s user=%s: %s" chat_id
                        user_id err);
                  Lwt.return (`Ok {|{"code":0}|})))
  with _ -> Lwt.return (`Ok {|{"code":0}|})

let start ~(config : Runtime_config.t) ~(session_manager : Session.t) =
  match config.channels.lark with
  | None ->
      Logs.info (fun m -> m "No Lark config found, skipping");
      Lwt.return_unit
  | Some lark_config ->
      if lark_config.mode = "webhook" then begin
        Logs.info (fun m ->
            m "Lark channel configured in webhook mode (endpoint=%s)"
              lark_config.endpoint);
        Lwt.return_unit
      end
      else begin
        (* WebSocket mode - for now log a notice; full WSS gateway
           requires Lark-specific connection endpoint discovery *)
        Logs.info (fun m ->
            m
              "Lark channel: websocket mode configured (endpoint=%s); webhook \
               mode is recommended"
              lark_config.endpoint);
        ignore session_manager;
        Lwt.return_unit
      end
