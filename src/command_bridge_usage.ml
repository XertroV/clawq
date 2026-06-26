(* Usage, models, provider, and cost CLI handlers.
   Split from command_bridge_helpers.ml; re-exported there via [include]. *)
open Command_bridge_gateway

let cmd_models args = Command_bridge_models.cmd_models ~get_db ~get_config args

let parse_since_arg args =
  let rec find = function
    | "--since" :: v :: _ -> Some v
    | _ :: rest -> find rest
    | [] -> None
  in
  match find args with
  | None -> None
  | Some period ->
      let now = Unix.gettimeofday () in
      let ts =
        match String.lowercase_ascii period with
        | "today" ->
            let tm = Unix.gmtime now in
            let midnight =
              { tm with Unix.tm_hour = 0; tm_min = 0; tm_sec = 0 }
            in
            let local_ts, _ = Unix.mktime midnight in
            let dummy_gm = Unix.gmtime 0.0 in
            let dummy_local = Unix.localtime 0.0 in
            let tz_offset_s =
              float_of_int
                (((dummy_local.Unix.tm_hour - dummy_gm.Unix.tm_hour) * 3600)
                + ((dummy_local.Unix.tm_min - dummy_gm.Unix.tm_min) * 60))
            in
            Some (local_ts -. tz_offset_s)
        | "7d" -> Some (now -. 604800.0)
        | "30d" -> Some (now -. 2592000.0)
        | "90d" -> Some (now -. 7776000.0)
        | _ -> None
      in
      ts

let parse_string_arg flag args =
  let rec find = function
    | f :: v :: _ when f = flag -> Some v
    | _ :: rest -> find rest
    | [] -> None
  in
  find args

let parse_int_arg flag args =
  match parse_string_arg flag args with
  | Some s -> ( try Some (int_of_string s) with _ -> None)
  | None -> None

let cmd_usage_history args =
  let db = get_db () in
  Provider_quota.set_db db;
  let provider = parse_string_arg "--provider" args in
  let since = parse_since_arg args in
  let limit =
    match parse_int_arg "--limit" args with Some n -> Some n | None -> Some 50
  in
  let json_mode = List.mem "--json" args in
  let entries =
    match provider with
    | Some p ->
        Provider_quota.history_for_provider ~db ~provider:p ?since ?limit ()
    | None -> Provider_quota.history_all ~db ?since ?limit ()
  in
  if entries = [] then "No quota history found."
  else if json_mode then
    let arr = `List (List.map Provider_quota.history_entry_to_json entries) in
    Yojson.Safe.pretty_to_string arr
  else
    let columns =
      Table_format.
        [
          { header = "TIME"; align = Left; min_width = 19; flex = false };
          { header = "PROVIDER"; align = Left; min_width = 10; flex = false };
          { header = "SESSION"; align = Right; min_width = 7; flex = false };
          { header = "WEEKLY"; align = Right; min_width = 7; flex = false };
          { header = "MONTHLY"; align = Right; min_width = 7; flex = false };
          { header = "STATUS"; align = Left; min_width = 6; flex = false };
        ]
    in
    let rows =
      List.map
        (fun (entry : Provider_quota.history_entry) ->
          let sess, week, mon =
            match entry.h_state with
            | Provider_quota.Unknown _ -> ("-", "-", "-")
            | Provider_quota.Known { session; weekly; monthly } ->
                let fmt_pct = function
                  | None -> "-"
                  | Some w -> Printf.sprintf "%.0f%%" w.Provider_quota.used_pct
                in
                (fmt_pct session, fmt_pct weekly, fmt_pct monthly)
          in
          let status =
            Provider_quota.status_label
              {
                provider_name = entry.h_provider;
                state = entry.h_state;
                fetched_at = entry.h_fetched_at;
              }
          in
          [ entry.h_recorded_at; entry.h_provider; sess; week; mon; status ])
        entries
    in
    "Quota History:\n" ^ Table_format.render columns rows

let cmd_usage_purge args =
  let db = get_db () in
  Provider_quota.set_db db;
  let now = Unix.gettimeofday () in
  let before =
    match args with
    | [] -> now -. 7776000.0
    | period :: _ -> (
        match String.lowercase_ascii period with
        | "7d" -> now -. 604800.0
        | "30d" -> now -. 2592000.0
        | "90d" -> now -. 7776000.0
        | "all" -> now +. 1.0
        | _ -> now -. 7776000.0)
  in
  let count = Provider_quota.purge_history ~db ~before () in
  Printf.sprintf "Purged %d quota history entries." count

let cmd_active _args =
  let db = get_db () in
  let cfg = get_config () in
  Provider_quota.set_db db;
  Provider_quota.set_cache_ttl cfg.quota_cache_ttl_s;
  Slash_commands.format_active ~connector:Format_adapter.Plain ~db ~config:cfg
    ()

let cmd_usage args =
  match args with
  | "history" :: rest -> cmd_usage_history rest
  | "purge" :: rest -> cmd_usage_purge rest
  | _ ->
      let refresh = List.mem "--refresh" args || List.mem "-r" args in
      let cfg = get_config () in
      let db = get_db () in
      Provider_quota.set_db db;
      Provider_quota.set_cache_ttl cfg.quota_cache_ttl_s;
      let results =
        if refresh then
          let refreshed =
            Lwt_main.run (Provider_quota.refresh_all ~config:cfg ())
          in
          List.map (fun pq -> (pq.Provider_quota.provider_name, pq)) refreshed
        else Provider_quota.get_all_cached ()
      in
      if results = [] then
        if refresh then "No providers configured."
        else
          "No cached quota data. Run 'clawq usage --refresh' to fetch current \
           data."
      else
        let threshold_for name =
          match List.assoc_opt name cfg.providers with
          | Some pc -> Option.value ~default:0.85 pc.quota_threshold
          | None -> 0.85
        in
        let columns =
          Table_format.
            [
              {
                header = "PROVIDER";
                align = Left;
                min_width = 10;
                flex = false;
              };
              { header = "SESSION"; align = Right; min_width = 7; flex = false };
              { header = "WEEKLY"; align = Right; min_width = 7; flex = false };
              { header = "MONTHLY"; align = Right; min_width = 7; flex = false };
              { header = "STATUS"; align = Left; min_width = 6; flex = false };
            ]
        in
        let rows =
          List.map
            (fun (_name, pq) ->
              let sess, week, mon =
                match pq.Provider_quota.state with
                | Provider_quota.Unknown _ -> ("-", "-", "-")
                | Provider_quota.Known { session; weekly; monthly } ->
                    let fmt_pct = function
                      | None -> "-"
                      | Some w ->
                          Printf.sprintf "%.0f%%" w.Provider_quota.used_pct
                    in
                    (fmt_pct session, fmt_pct weekly, fmt_pct monthly)
              in
              let status =
                Provider_quota.status_label
                  ~threshold:(threshold_for pq.Provider_quota.provider_name)
                  pq
              in
              [ pq.Provider_quota.provider_name; sess; week; mon; status ])
            results
        in
        "Provider Usage:\n" ^ Table_format.render columns rows

let cmd_provider args =
  match args with
  | "quota" :: rest -> (
      let cfg = get_config () in
      let db = get_db () in
      Provider_quota.set_db db;
      let target = match rest with [ name ] -> Some name | _ -> None in
      match target with
      | Some name when not (List.mem_assoc name cfg.providers) ->
          Printf.sprintf "Provider '%s' not configured" name
      | _ ->
          let providers_to_check =
            match target with
            | Some name -> (
                match List.assoc_opt name cfg.providers with
                | Some pc -> [ (name, pc) ]
                | None -> [])
            | None -> cfg.providers
          in
          Provider_quota.set_cache_ttl cfg.quota_cache_ttl_s;
          let results =
            Lwt_main.run
              (Lwt_list.map_s
                 (fun (name, pc) ->
                   Provider_quota.fetch_for_provider ~config:pc ~name ())
                 providers_to_check)
          in
          let threshold_for name =
            match List.assoc_opt name cfg.providers with
            | Some pc -> Option.value ~default:0.85 pc.quota_threshold
            | None -> 0.85
          in
          if results = [] then "No providers configured."
          else
            let lines =
              List.map
                (fun pq ->
                  let summary = Provider_quota.to_summary_string pq in
                  let label =
                    Provider_quota.status_label
                      ~threshold:(threshold_for pq.Provider_quota.provider_name)
                      pq
                  in
                  summary ^ "  " ^ label)
                results
            in
            String.concat "\n" lines)
  | "list" :: _ | [] -> cmd_models []
  | unknown :: _ ->
      Printf.sprintf
        "Unknown provider subcommand: %s\nUsage: provider quota [NAME]" unknown

let cost_summary_columns =
  Table_format.
    [
      { header = "PERIOD"; align = Left; min_width = 12; flex = false };
      { header = "COST"; align = Right; min_width = 8; flex = false };
      { header = "TURNS"; align = Right; min_width = 5; flex = false };
      { header = "PROMPT"; align = Right; min_width = 6; flex = false };
      { header = "ADDED"; align = Right; min_width = 6; flex = false };
      { header = "COMPLETION"; align = Right; min_width = 6; flex = false };
    ]

let cost_summary_row label (s : Request_stats.summary) =
  [
    label;
    Printf.sprintf "$%.4f" s.total_cost_usd;
    string_of_int s.total_turns;
    Request_stats.format_tokens s.total_prompt_tokens;
    Request_stats.format_tokens s.total_added_prompt_tokens;
    Request_stats.format_tokens s.total_completion_tokens;
  ]

let summary_to_json label (s : Request_stats.summary) =
  `Assoc
    [
      ("period", `String label);
      ("cost_usd", `Float s.total_cost_usd);
      ("prompt_tokens", `Int s.total_prompt_tokens);
      ("completion_tokens", `Int s.total_completion_tokens);
      ("added_prompt_tokens", `Int s.total_added_prompt_tokens);
      ("turns", `Int s.total_turns);
    ]

let cmd_costs args =
  let db = get_db () in
  let json_mode = List.mem "--json" args in
  let args = List.filter (fun a -> a <> "--json") args in
  match args with
  | [] ->
      let today =
        Request_stats.summary_for_period ~db
          ~since:"datetime('now', 'start of day')"
      in
      let week =
        Request_stats.summary_for_period ~db ~since:"datetime('now', '-7 days')"
      in
      let month =
        Request_stats.summary_for_period ~db
          ~since:"datetime('now', '-30 days')"
      in
      let all = Request_stats.total_summary ~db in
      if json_mode then
        Yojson.Safe.pretty_to_string
          (`List
             [
               summary_to_json "today" today;
               summary_to_json "7_days" week;
               summary_to_json "30_days" month;
               summary_to_json "all_time" all;
             ])
      else if all.total_turns = 0 then "No cost data recorded yet."
      else
        let rows =
          [
            cost_summary_row "Today" today;
            cost_summary_row "Last 7 days" week;
            cost_summary_row "Last 30 days" month;
            cost_summary_row "All time" all;
          ]
        in
        "Cost Summary:\n" ^ Table_format.render cost_summary_columns rows
  | [ "session" ] ->
      let sessions = Request_stats.summary_by_session ~db in
      if json_mode then
        Yojson.Safe.pretty_to_string
          (`List
             (List.map
                (fun (ss : Request_stats.session_summary) ->
                  `Assoc
                    [
                      ("session_key", `String ss.session_key);
                      ("cost_usd", `Float ss.summary.total_cost_usd);
                      ("prompt_tokens", `Int ss.summary.total_prompt_tokens);
                      ( "completion_tokens",
                        `Int ss.summary.total_completion_tokens );
                      ( "added_prompt_tokens",
                        `Int ss.summary.total_added_prompt_tokens );
                      ("turns", `Int ss.summary.total_turns);
                      ("first_request", `String ss.first_request);
                      ("last_request", `String ss.last_request);
                    ])
                sessions))
      else if sessions = [] then "No cost data recorded yet."
      else
        let session_columns =
          Table_format.
            [
              { header = "SESSION"; align = Left; min_width = 10; flex = true };
              { header = "COST"; align = Right; min_width = 8; flex = false };
              { header = "TURNS"; align = Right; min_width = 5; flex = false };
              { header = "PROMPT"; align = Right; min_width = 6; flex = false };
              { header = "ADDED"; align = Right; min_width = 6; flex = false };
              {
                header = "COMPLETION";
                align = Right;
                min_width = 6;
                flex = false;
              };
            ]
        in
        let rows =
          List.map
            (fun (ss : Request_stats.session_summary) ->
              cost_summary_row ss.session_key ss.summary)
            sessions
        in
        "Session Costs:\n" ^ Table_format.render session_columns rows
  | [ "session"; key ] ->
      let s = Request_stats.summary_for_session ~db ~session_key:key in
      if json_mode then Yojson.Safe.pretty_to_string (summary_to_json key s)
      else if s.total_turns = 0 then
        Printf.sprintf "No cost data for session '%s'." key
      else
        let rows = [ cost_summary_row "Total" s ] in
        Printf.sprintf "Costs for %s:\n" key
        ^ Table_format.render cost_summary_columns rows
  | [ "model" ] ->
      let models = Request_stats.summary_by_model ~db in
      if json_mode then
        Yojson.Safe.pretty_to_string
          (`List
             (List.map
                (fun (ms : Request_stats.model_summary) ->
                  `Assoc
                    [
                      ("model", `String ms.model);
                      ("provider", `String ms.provider);
                      ("cost_usd", `Float ms.summary.total_cost_usd);
                      ("prompt_tokens", `Int ms.summary.total_prompt_tokens);
                      ( "completion_tokens",
                        `Int ms.summary.total_completion_tokens );
                      ("turns", `Int ms.summary.total_turns);
                    ])
                models))
      else if models = [] then "No cost data recorded yet."
      else
        let model_columns =
          Table_format.
            [
              { header = "MODEL"; align = Left; min_width = 15; flex = true };
              { header = "COST"; align = Right; min_width = 8; flex = false };
              { header = "TURNS"; align = Right; min_width = 5; flex = false };
              { header = "PROMPT"; align = Right; min_width = 6; flex = false };
              {
                header = "COMPLETION";
                align = Right;
                min_width = 6;
                flex = false;
              };
            ]
        in
        let rows =
          List.map
            (fun (ms : Request_stats.model_summary) ->
              [
                ms.provider ^ ":" ^ ms.model;
                Printf.sprintf "$%.4f" ms.summary.total_cost_usd;
                string_of_int ms.summary.total_turns;
                Request_stats.format_tokens ms.summary.total_prompt_tokens;
                Request_stats.format_tokens ms.summary.total_completion_tokens;
              ])
            models
        in
        "Model Costs:\n" ^ Table_format.render model_columns rows
  | [ "provider" ] ->
      let providers = Request_stats.summary_by_provider ~db in
      if json_mode then
        Yojson.Safe.pretty_to_string
          (`List
             (List.map
                (fun (prov, s) ->
                  `Assoc
                    [
                      ("provider", `String prov);
                      ("cost_usd", `Float s.Request_stats.total_cost_usd);
                      ("prompt_tokens", `Int s.total_prompt_tokens);
                      ("completion_tokens", `Int s.total_completion_tokens);
                      ("turns", `Int s.total_turns);
                    ])
                providers))
      else if providers = [] then "No cost data recorded yet."
      else
        let provider_columns =
          Table_format.
            [
              {
                header = "PROVIDER";
                align = Left;
                min_width = 10;
                flex = false;
              };
              { header = "COST"; align = Right; min_width = 8; flex = false };
              { header = "TURNS"; align = Right; min_width = 5; flex = false };
              { header = "PROMPT"; align = Right; min_width = 6; flex = false };
              {
                header = "COMPLETION";
                align = Right;
                min_width = 6;
                flex = false;
              };
            ]
        in
        let rows =
          List.map
            (fun (prov, (s : Request_stats.summary)) ->
              [
                prov;
                Printf.sprintf "$%.4f" s.total_cost_usd;
                string_of_int s.total_turns;
                Request_stats.format_tokens s.total_prompt_tokens;
                Request_stats.format_tokens s.total_completion_tokens;
              ])
            providers
        in
        "Provider Costs:\n" ^ Table_format.render provider_columns rows
  | _ ->
      "Usage: clawq costs [subcommand] [--json]\n\n\
       Subcommands:\n\
      \  (default)       Cost summary by time period\n\
      \  session [KEY]   Per-session cost breakdown\n\
      \  model           Per-model cost breakdown\n\
      \  provider        Per-provider cost breakdown"
