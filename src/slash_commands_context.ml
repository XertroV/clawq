let dash = "-"
let opt_value = Option.value ~default:dash
let format_int_opt = function Some n -> string_of_int n | None -> dash

type context_usage_source = Active_history | Stored_history

let format_token_count n = Request_stats.format_tokens n ^ " tokens"

let format_window = function
  | Some n -> format_token_count n
  | None -> "unknown"

let context_window_fallback = 128000

let effective_context_window_for_model ~configured_limits model =
  Runtime_config.context_window_for_model ~configured_limits model
  |> Option.value ~default:context_window_fallback
  |> Option.some

let source_label = function
  | Active_history -> "active history"
  | Stored_history -> "stored history"

let format_context_usage ~source ~estimated_tokens ~context_window =
  let percent =
    min 100.0
      (100.0 *. float_of_int estimated_tokens /. float_of_int context_window)
  in
  Printf.sprintf "%.1f%% (%s/%s; %s)" percent
    (format_token_count estimated_tokens)
    (format_token_count context_window)
    (source_label source)

let stored_context_usage ~db ~session_key ~context_window =
  match context_window with
  | Some window when window > 0 -> (
      match Memory.load_history ~db ~session_key with
      | [] -> None
      | history ->
          Some (Stored_history, Agent.estimate_history_tokens history, window))
  | _ -> None

let context_usage ~db ~session_mgr ~session_key ~context_window =
  match Session.get_context_usage_percent session_mgr ~key:session_key with
  | Some (_, estimated_tokens, window) when window > 0 ->
      Some (Active_history, estimated_tokens, window)
  | _ ->
      Option.bind db (fun db ->
          stored_context_usage ~db ~session_key ~context_window)

let format_context_usage_row = function
  | Some (source, estimated_tokens, window) ->
      format_context_usage ~source ~estimated_tokens ~context_window:window
  | None -> "unknown (no active or stored history)"

let compaction_threshold_tokens ~context_window ~threshold =
  match context_window with
  | Some window when window > 0 -> Some (window * threshold / 100)
  | _ -> None

let format_compaction_token_threshold ~context_window ~threshold =
  match compaction_threshold_tokens ~context_window ~threshold with
  | Some tokens ->
      Printf.sprintf "%s (%d%% of window)" (format_token_count tokens) threshold
  | None -> Printf.sprintf "unknown (%d%% of window)" threshold

let effective_max_messages config =
  let m = config.Runtime_config.memory.max_messages_per_session in
  if m <= 0 then 500 else min m 500

let find_session_info ~db ~session_key =
  Memory.list_session_infos ~db ~prefix:session_key ()
  |> List.find_opt (fun (i : Memory.session_info) ->
      i.session_key = session_key)

let format ~connector ~session_mgr ~session_key =
  let config = Session.get_config session_mgr in
  let model =
    Session.get_session_effective_model session_mgr ~key:session_key
  in
  let context_window =
    effective_context_window_for_model
      ~configured_limits:config.model_context_limits model
  in
  let threshold =
    Runtime_config.effective_compaction_threshold_percent config.memory
  in
  let db = Session.get_db session_mgr in
  let info = Option.bind db (fun db -> find_session_info ~db ~session_key) in
  let stats =
    match db with
    | Some db -> Request_stats.summary_for_session ~db ~session_key
    | None -> Request_stats.zero_summary
  in
  let current_context =
    context_usage ~db ~session_mgr ~session_key ~context_window
  in
  let max_messages = effective_max_messages config in
  let pending =
    match db with
    | Some db -> Some (Memory.queue_count ~db ~session_key)
    | None -> None
  in
  let channel =
    match info with
    | Some i -> (
        match i.channel with
        | Some c -> c
        | None -> (
            match Memory.parse_channel_from_session_key i.session_key with
            | Some c -> c
            | None -> dash))
    | None -> (
        match Runtime_config.channel_type_of_session_key session_key with
        | "" -> dash
        | c -> c)
  in
  let channel_id =
    match info with Some i -> opt_value i.channel_id | None -> dash
  in
  let state = match info with Some i -> opt_value i.turn | None -> dash in
  let message_count =
    match info with Some i -> Some i.message_count | None -> None
  in
  let archive_count =
    match info with Some i -> Some i.archived_epoch_count | None -> None
  in
  let keepalive =
    match info with
    | Some i -> if i.keepalive_enabled then "on" else "off"
    | None -> dash
  in
  let heartbeat =
    match info with
    | Some i -> if i.heartbeat_enabled then "on" else "off"
    | None -> dash
  in
  let last_active =
    match info with Some i -> opt_value i.last_active | None -> dash
  in
  let cwd =
    match info with Some i -> opt_value i.effective_cwd | None -> dash
  in
  let rows =
    [
      [ "Session"; session_key ];
      [ "Channel"; channel ];
      [ "Channel ID"; channel_id ];
      [ "State"; state ];
      [ "Model"; model ];
      [ "Context window"; format_window context_window ];
      [ "Estimated context usage"; format_context_usage_row current_context ];
      [ "Compaction threshold"; Printf.sprintf "%d%%" threshold ];
      [
        "Compaction token threshold";
        format_compaction_token_threshold ~context_window ~threshold;
      ];
      [ "Max messages before compaction"; string_of_int max_messages ];
      [ "Messages"; format_int_opt message_count ];
      [ "Archives"; format_int_opt archive_count ];
      [ "Pending inbound"; format_int_opt pending ];
      [ "Prompt tokens"; Request_stats.format_tokens stats.total_prompt_tokens ];
      [
        "Completion tokens";
        Request_stats.format_tokens stats.total_completion_tokens;
      ];
      [ "Cached tokens"; Request_stats.format_tokens stats.total_cached_tokens ];
      [
        "Added prompt tokens";
        Request_stats.format_tokens stats.total_added_prompt_tokens;
      ];
      [ "Turns"; string_of_int stats.total_turns ];
      [ "Keepalive"; keepalive ];
      [ "Heartbeat"; heartbeat ];
      [ "Last active"; last_active ];
      [ "Working dir"; cwd ];
    ]
  in
  let columns =
    Table_format.
      [
        { header = "FIELD"; align = Left; min_width = 20; flex = false };
        { header = "VALUE"; align = Left; min_width = 20; flex = true };
      ]
  in
  Format_adapter.bold connector "Session Context"
  ^ "\n\n"
  ^ Format_adapter.render_table connector ~max_width:72 columns rows
