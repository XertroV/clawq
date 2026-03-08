type settings = { show_thinking : bool; show_tool_calls : bool }
type t = { thinking_buf : Buffer.t; content_buf : Buffer.t }

let create () =
  { thinking_buf = Buffer.create 256; content_buf = Buffer.create 1024 }

let truncate_text ?(max_chars = 800) text =
  if String.length text <= max_chars then text
  else String.sub text 0 max_chars ^ "..."

let tool_call_message ~name ~result ~is_error =
  if is_error then
    Printf.sprintf "\xF0\x9F\x94\xA7 %s \xE2\x9C\x97 %s" name
      (truncate_text ~max_chars:200 result)
  else Printf.sprintf "\xF0\x9F\x94\xA7 %s \xE2\x9C\x93" name

let thinking_message text = "Thinking:\n" ^ text

let on_chunk t ~(settings : settings) ~notify = function
  | Provider.ThinkingDelta text ->
      if settings.show_thinking then Buffer.add_string t.thinking_buf text;
      Lwt.return_unit
  | Provider.Delta text ->
      Buffer.add_string t.content_buf text;
      Lwt.return_unit
  | Provider.ToolStart _ -> Lwt.return_unit
  | Provider.ToolResult { name; result; is_error; _ } ->
      if settings.show_tool_calls then
        notify (tool_call_message ~name ~result ~is_error)
      else Lwt.return_unit
  | Provider.ToolCallDelta _ | Provider.ToolOutputDelta _ | Provider.Done ->
      Lwt.return_unit

let thinking_text t = Buffer.contents t.thinking_buf
let content_text t = Buffer.contents t.content_buf
