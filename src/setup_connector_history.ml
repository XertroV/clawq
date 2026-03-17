(* setup_connector_history.ml — Interactive setup wizard for connector history *)

let validate_max_messages s =
  match int_of_string_opt s with
  | Some v when v >= 1 && v <= 128 -> Ok s
  | Some _ -> Error "max_messages must be between 1 and 128."
  | None -> Error "max_messages must be a valid integer."

let validate_max_age_days s =
  match int_of_string_opt s with
  | Some v when v >= 1 -> Ok s
  | Some _ -> Error "max_age_days must be >= 1."
  | None -> Error "max_age_days must be a valid integer."

let build_json ~enabled ~persist_to_db ~max_messages ~max_age_days =
  Setup_common.build_section_json ~section_name:"connector_history"
    [
      ("enabled", `Bool enabled);
      ("persist_to_db", `Bool persist_to_db);
      ("max_messages", `Int max_messages);
      ("max_age_days", `Int max_age_days);
    ]

let post_setup_instructions =
  {|
  Connector history configuration:

    1. enabled: Save unaddressed group chat messages (Teams/Discord).
       When false (default), no overhead — messages are dropped as before.
    2. persist_to_db: Also persist captured messages to SQLite for
       cross-restart survival. Default false (in-memory only).
    3. max_messages: Per-conversation ring buffer size (1-128, default 50).
    4. max_age_days: DB retention period in days (default 7). Rows older
       than this are purged hourly.

  After saving:

    - The change takes effect on the next message (no restart needed).
    - Use /inject_connector_history [N] in Teams/Discord group chats
      to load captured messages into the agent's context.
|}

let load_existing () =
  Setup_common.load_config_field (fun cfg -> cfg.connector_history)

let run () =
  let existing = load_existing () in
  let default = Runtime_config.default.connector_history in
  let get f = match existing with Some c -> f c | None -> f default in
  let enabled =
    Setup_tui.make_bool_field ~key:"e" ~label:"Enabled"
      ~menu_label:"Toggle connector history"
      ~description:
        "Save unaddressed group chat messages (Teams/Discord) for later \
         retrieval."
      ~default:(get (fun c -> c.Runtime_config.enabled))
      ()
  in
  let persist_to_db =
    Setup_tui.make_bool_field ~key:"p" ~label:"Persist to DB"
      ~menu_label:"Toggle DB persistence"
      ~description:
        "Also write messages to SQLite so history survives daemon restarts."
      ~default:(get (fun c -> c.Runtime_config.persist_to_db))
      ()
  in
  let max_messages =
    Setup_tui.make_int_field ~key:"m" ~label:"Max messages"
      ~menu_label:"Set per-conversation buffer size (1-128)"
      ~description:
        "Maximum messages kept per conversation. Oldest dropped when full."
      ~validate:validate_max_messages
      ~default:(get (fun c -> c.Runtime_config.max_messages))
      ()
  in
  let max_age_days =
    Setup_tui.make_int_field ~key:"a" ~label:"Max age (days)"
      ~menu_label:"Set DB retention period (days)"
      ~description:"DB rows older than this are purged hourly."
      ~validate:validate_max_age_days
      ~default:(get (fun c -> c.Runtime_config.max_age_days))
      ()
  in
  let spec : Setup_tui.wizard_spec =
    {
      title = " Connector History ";
      docs_url = "https://clawq.org/connector-history/";
      fields = [ enabled; persist_to_db; max_messages; max_age_days ];
      extra_actions = [];
      build_json =
        (fun () ->
          build_json
            ~enabled:(Setup_tui.get_bool enabled)
            ~persist_to_db:(Setup_tui.get_bool persist_to_db)
            ~max_messages:(Setup_tui.get_int max_messages)
            ~max_age_days:(Setup_tui.get_int max_age_days));
      pre_save_check = (fun () -> Ok ());
      post_instructions = (fun () -> post_setup_instructions);
    }
  in
  Setup_tui.run_wizard spec
