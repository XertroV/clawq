let make_relay_registry
    ~(ask_fn :
       session_key:string ->
       questions:Tools_builtin.question_item list ->
       Tools_builtin.question_result list Lwt.t) ~session_key =
  let registry = Tool_registry.create () in
  let tool =
    {
      Tool.name = "ask_user_question";
      description =
        "Ask the user one or more clarifying questions and wait for answers. \
         Questions are sent to the user's active channel (Telegram, Discord, \
         Slack, web). Returns JSON array of {question, answer, notes?}.";
      parameters_schema = Tools_builtin.ask_user_question_schema;
      invoke =
        (fun ?context:_ args ->
          let open Lwt.Syntax in
          let questions = Tools_builtin.parse_questions args in
          if questions = [] then
            Lwt.return
              "Error: questions array is empty. Provide at least one question \
               object with 'type' and 'question' fields."
          else
            Lwt.catch
              (fun () ->
                let* results = ask_fn ~session_key ~questions in
                Lwt.return (Tools_builtin.serialize_question_results results))
              (fun exn ->
                Lwt.return
                  (Printf.sprintf "Error: question failed: %s"
                     (Printexc.to_string exn))));
      invoke_stream = None;
      risk_level = Tool.Low;
      deferred = false;
    }
  in
  Tool_registry.register registry tool;
  registry

let handle ~(registry : Tool_registry.t) ~body =
  let open Lwt.Syntax in
  match try Ok (Yojson.Safe.from_string body) with exn -> Error exn with
  | Error _ ->
      let err =
        Mcp_server.jsonrpc_error ~id:`Null ~code:(-32700) ~message:"Parse error"
      in
      Lwt.return (200, Yojson.Safe.to_string err)
  | Ok json -> (
      let* response = Mcp_server.handle_request ~registry json in
      match response with
      | None -> Lwt.return (200, {|{"jsonrpc":"2.0"}|})
      | Some resp -> Lwt.return (200, Yojson.Safe.to_string resp))
