open Yojson.Safe.Util

let parse_max_concurrent_native_agents ~default = function
  | `Int n when n > 0 -> Some n
  | `Int _ | `Null -> None
  | _ -> default

let parse ad ~(default : Runtime_config.agent_defaults) :
    Runtime_config.agent_defaults =
  try
    let primary_model =
      try ad |> member "primary_model" |> to_string
      with _ -> default.primary_model
    in
    let subagent_default_model =
      try
        match ad |> member "subagent_default_model" with
        | `String s when String.trim s <> "" -> Some (String.trim s)
        | _ -> None
      with _ -> default.subagent_default_model
    in
    let system_prompt =
      try ad |> member "system_prompt" |> to_string
      with _ -> default.system_prompt
    in
    let max_tool_iterations =
      try ad |> member "max_tool_iterations" |> to_int
      with _ -> default.max_tool_iterations
    in
    let tool_search_enabled =
      try ad |> member "tool_search_enabled" |> to_bool
      with _ -> default.tool_search_enabled
    in
    let reasoning_effort =
      try Some (ad |> member "reasoning_effort" |> to_string)
      with _ -> default.reasoning_effort
    in
    let show_thinking =
      try ad |> member "show_thinking" |> to_bool
      with _ -> default.show_thinking
    in
    let drop_thinking =
      try ad |> member "drop_thinking" |> to_bool
      with _ -> default.drop_thinking
    in
    let show_tool_calls =
      try ad |> member "show_tool_calls" |> to_bool
      with _ -> default.show_tool_calls
    in
    let tool_status_mode =
      try ad |> member "tool_status_mode" |> to_string
      with _ -> default.tool_status_mode
    in
    let send_continuation_checkin =
      try ad |> member "send_continuation_checkin" |> to_bool
      with _ -> default.send_continuation_checkin
    in
    let autonomous_continuation_delay =
      try ad |> member "autonomous_continuation_delay" |> to_float
      with _ -> default.autonomous_continuation_delay
    in
    let autonomous_continuation_enabled =
      try ad |> member "autonomous_continuation_enabled" |> to_bool
      with _ -> default.autonomous_continuation_enabled
    in
    let task_tree_notifications =
      try ad |> member "task_tree_notifications" |> to_bool
      with _ -> default.task_tree_notifications
    in
    let max_concurrent_native_agents =
      try
        parse_max_concurrent_native_agents
          ~default:default.max_concurrent_native_agents
          (ad |> member "max_concurrent_native_agents")
      with _ -> default.max_concurrent_native_agents
    in
    {
      primary_model;
      subagent_default_model;
      system_prompt;
      max_tool_iterations;
      tool_search_enabled;
      reasoning_effort;
      show_thinking;
      drop_thinking;
      show_tool_calls;
      tool_status_mode;
      send_continuation_checkin;
      autonomous_continuation_delay;
      autonomous_continuation_enabled;
      task_tree_notifications;
      max_concurrent_native_agents;
    }
  with _ -> default
