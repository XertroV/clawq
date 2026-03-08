let test_tool_call_message_success () =
  let message =
    Stream_visibility.tool_call_message ~name:"bash" ~result:"ok"
      ~is_error:false
  in
  Alcotest.(check string)
    "tool call success message" "\xF0\x9F\x94\xA7 bash \xE2\x9C\x93" message

let test_tool_call_message_error_truncates () =
  let result = String.make 300 'x' in
  let message =
    Stream_visibility.tool_call_message ~name:"bash" ~result ~is_error:true
  in
  Alcotest.(check bool)
    "tool call error has prefix" true
    (String.starts_with ~prefix:"\xF0\x9F\x94\xA7 bash \xE2\x9C\x97 " message);
  Alcotest.(check bool)
    "tool call error truncated" true
    (String.ends_with ~suffix:"..." message)

let test_thinking_message_prefixes_content () =
  Alcotest.(check string)
    "thinking message" "Thinking:\nplan first"
    (Stream_visibility.thinking_message "plan first")

let suite =
  [
    Alcotest.test_case "tool call success message" `Quick
      test_tool_call_message_success;
    Alcotest.test_case "tool call error truncates" `Quick
      test_tool_call_message_error_truncates;
    Alcotest.test_case "thinking message prefixes content" `Quick
      test_thinking_message_prefixes_content;
  ]
