let format_session ~connector ~db action =
  match action with
  | Slash_commands_fmt.SessionList ->
      let infos = Memory.list_session_infos ~db () in
      if infos = [] then "No sessions found."
      else
        let columns =
          Table_format.
            [
              { header = "SESSION"; align = Left; min_width = 12; flex = true };
              { header = "STATE"; align = Left; min_width = 6; flex = false };
              { header = "CHANNEL"; align = Left; min_width = 7; flex = false };
              { header = "MSGS"; align = Right; min_width = 4; flex = false };
              { header = "COST"; align = Right; min_width = 8; flex = false };
              {
                header = "LAST ACTIVE";
                align = Left;
                min_width = 10;
                flex = false;
              };
            ]
        in
        let rows =
          List.map
            (fun (info : Memory.session_info) ->
              let state = match info.turn with Some t -> t | None -> "idle" in
              let channel =
                match info.channel with
                | Some c -> c
                | None -> (
                    match
                      Memory.parse_channel_from_session_key info.session_key
                    with
                    | Some c -> c
                    | None -> "-")
              in
              let stats =
                Request_stats.summary_for_session ~db
                  ~session_key:info.session_key
              in
              let cost =
                if stats.total_cost_usd > 0.0 then
                  Printf.sprintf "$%.4f" stats.total_cost_usd
                else "-"
              in
              let last_active =
                match info.last_active with Some ts -> ts | None -> "-"
              in
              [
                info.session_key;
                state;
                channel;
                string_of_int info.message_count;
                cost;
                last_active;
              ])
            infos
        in
        Format_adapter.bold connector "Sessions"
        ^ "\n\n"
        ^ Format_adapter.render_table connector ~max_width:80 columns rows
  | SessionShow key -> (
      let infos =
        Memory.list_session_infos ~db ~prefix:key ()
        |> List.filter (fun (i : Memory.session_info) -> i.session_key = key)
      in
      match infos with
      | [] -> Printf.sprintf "Session '%s' not found." key
      | info :: _ ->
          let stats =
            Request_stats.summary_for_session ~db ~session_key:info.session_key
          in
          let pending = Memory.queue_count ~db ~session_key:info.session_key in
          let channel =
            match info.channel with
            | Some c -> c
            | None -> (
                match
                  Memory.parse_channel_from_session_key info.session_key
                with
                | Some c -> c
                | None -> "-")
          in
          let state = match info.turn with Some t -> t | None -> "idle" in
          let kv_columns =
            Table_format.
              [
                { header = "FIELD"; align = Left; min_width = 12; flex = false };
                { header = "VALUE"; align = Left; min_width = 20; flex = true };
              ]
          in
          let rows =
            [
              [ "Session"; info.session_key ];
              [ "State"; state ];
              [ "Channel"; channel ];
              [ "Messages"; string_of_int info.message_count ];
              [ "Archives"; string_of_int info.archived_epoch_count ];
              [ "Pending"; string_of_int pending ];
              [ "Keepalive"; (if info.keepalive_enabled then "on" else "off") ];
              [ "Heartbeat"; (if info.heartbeat_enabled then "on" else "off") ];
              [ "Cost"; Printf.sprintf "$%.4f" stats.total_cost_usd ];
              [ "Turns"; string_of_int stats.total_turns ];
              [
                "Prompt tokens";
                Request_stats.format_tokens stats.total_prompt_tokens;
              ];
              [
                "Completion tokens";
                Request_stats.format_tokens stats.total_completion_tokens;
              ];
              [
                "Last active";
                (match info.last_active with Some ts -> ts | None -> "-");
              ];
              [
                "Working dir";
                (match info.effective_cwd with Some d -> d | None -> "-");
              ];
            ]
          in
          Format_adapter.bold connector
            (Printf.sprintf "Session: %s" info.session_key)
          ^ "\n\n"
          ^ Format_adapter.render_table connector ~max_width:60 kv_columns rows)
