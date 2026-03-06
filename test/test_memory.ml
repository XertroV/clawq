(* Tests for Memory module *)

let mk_msg role content = Provider.make_message ~role ~content

(* --- Init tests --- *)

let test_init_creates_db () =
  let db = Memory.init ~db_path:":memory:" () in
  (* If we get here without exception, db was created *)
  ignore db

let test_init_search_enabled () =
  let db = Memory.init ~db_path:":memory:" ~search_enabled:true () in
  ignore db

let test_init_search_disabled () =
  let db = Memory.init ~db_path:":memory:" ~search_enabled:false () in
  ignore db

let test_init_double_call () =
  (* Second init on same path should not fail for :memory: (separate db) *)
  let db1 = Memory.init ~db_path:":memory:" () in
  let db2 = Memory.init ~db_path:":memory:" () in
  ignore db1;
  ignore db2

(* --- store_message tests --- *)

let test_store_message_inserts () =
  let db = Memory.init ~db_path:":memory:" () in
  Memory.store_message ~db ~session_key:"s1" (mk_msg "user" "hello");
  let msgs = Memory.load_history ~db ~session_key:"s1" in
  Alcotest.(check int) "1 message stored" 1 (List.length msgs)

let test_store_message_role_preserved () =
  let db = Memory.init ~db_path:":memory:" () in
  Memory.store_message ~db ~session_key:"s1" (mk_msg "assistant" "hi there");
  let msgs = Memory.load_history ~db ~session_key:"s1" in
  let m = List.hd msgs in
  Alcotest.(check string) "role is assistant" "assistant" m.role

let test_store_message_content_preserved () =
  let db = Memory.init ~db_path:":memory:" () in
  Memory.store_message ~db ~session_key:"s1" (mk_msg "user" "specific content");
  let msgs = Memory.load_history ~db ~session_key:"s1" in
  let m = List.hd msgs in
  Alcotest.(check string) "content preserved" "specific content" m.content

let test_store_multiple_messages () =
  let db = Memory.init ~db_path:":memory:" () in
  Memory.store_message ~db ~session_key:"s1" (mk_msg "user" "msg1");
  Memory.store_message ~db ~session_key:"s1" (mk_msg "assistant" "msg2");
  Memory.store_message ~db ~session_key:"s1" (mk_msg "user" "msg3");
  let msgs = Memory.load_history ~db ~session_key:"s1" in
  Alcotest.(check int) "3 messages" 3 (List.length msgs)

let test_store_message_with_tool_call_id () =
  let db = Memory.init ~db_path:":memory:" () in
  let msg =
    {
      Provider.role = "tool";
      content = "result";
      tool_calls = [];
      tool_call_id = Some "tcid-123";
      name = Some "file_read";
    }
  in
  Memory.store_message ~db ~session_key:"s1" msg;
  let msgs = Memory.load_history ~db ~session_key:"s1" in
  let m = List.hd msgs in
  Alcotest.(check (option string))
    "tool_call_id preserved" (Some "tcid-123") m.tool_call_id

let test_store_message_with_tool_calls () =
  let db = Memory.init ~db_path:":memory:" () in
  let tc =
    { Provider.id = "call-1"; function_name = "shell_exec"; arguments = "{}" }
  in
  let msg =
    {
      Provider.role = "assistant";
      content = "";
      tool_calls = [ tc ];
      tool_call_id = None;
      name = None;
    }
  in
  Memory.store_message ~db ~session_key:"s1" msg;
  let msgs = Memory.load_history ~db ~session_key:"s1" in
  let m = List.hd msgs in
  Alcotest.(check int) "1 tool call" 1 (List.length m.tool_calls);
  let got_tc = List.hd m.tool_calls in
  Alcotest.(check string) "tool call id" "call-1" got_tc.id;
  Alcotest.(check string) "function name" "shell_exec" got_tc.function_name

(* --- load_history tests --- *)

let test_load_history_order () =
  let db = Memory.init ~db_path:":memory:" () in
  Memory.store_message ~db ~session_key:"s1" (mk_msg "user" "first");
  Memory.store_message ~db ~session_key:"s1" (mk_msg "assistant" "second");
  Memory.store_message ~db ~session_key:"s1" (mk_msg "user" "third");
  let msgs = Memory.load_history ~db ~session_key:"s1" in
  let contents = List.map (fun (m : Provider.message) -> m.content) msgs in
  Alcotest.(check (list string))
    "messages in order"
    [ "first"; "second"; "third" ]
    contents

let test_load_history_empty_session () =
  let db = Memory.init ~db_path:":memory:" () in
  let msgs = Memory.load_history ~db ~session_key:"nonexistent" in
  Alcotest.(check int) "empty history" 0 (List.length msgs)

let test_load_history_session_isolation () =
  let db = Memory.init ~db_path:":memory:" () in
  Memory.store_message ~db ~session_key:"s1" (mk_msg "user" "session1-msg");
  Memory.store_message ~db ~session_key:"s2" (mk_msg "user" "session2-msg");
  let s1 = Memory.load_history ~db ~session_key:"s1" in
  let s2 = Memory.load_history ~db ~session_key:"s2" in
  Alcotest.(check int) "s1 has 1 message" 1 (List.length s1);
  Alcotest.(check int) "s2 has 1 message" 1 (List.length s2);
  Alcotest.(check string) "s1 content" "session1-msg" (List.hd s1).content;
  Alcotest.(check string) "s2 content" "session2-msg" (List.hd s2).content

(* --- clear_session tests --- *)

let test_clear_session () =
  let db = Memory.init ~db_path:":memory:" () in
  Memory.store_message ~db ~session_key:"s1" (mk_msg "user" "to delete");
  Memory.store_message ~db ~session_key:"s1" (mk_msg "assistant" "also delete");
  Memory.clear_session ~db ~session_key:"s1";
  let msgs = Memory.load_history ~db ~session_key:"s1" in
  Alcotest.(check int) "session cleared" 0 (List.length msgs)

let test_clear_session_isolates_others () =
  let db = Memory.init ~db_path:":memory:" () in
  Memory.store_message ~db ~session_key:"s1" (mk_msg "user" "s1");
  Memory.store_message ~db ~session_key:"s2" (mk_msg "user" "s2");
  Memory.clear_session ~db ~session_key:"s1";
  let s2 = Memory.load_history ~db ~session_key:"s2" in
  Alcotest.(check int) "s2 unaffected" 1 (List.length s2)

(* --- list_sessions tests --- *)

let test_list_sessions_empty () =
  let db = Memory.init ~db_path:":memory:" () in
  let sessions = Memory.list_sessions ~db in
  Alcotest.(check int) "no sessions" 0 (List.length sessions)

let test_list_sessions_single () =
  let db = Memory.init ~db_path:":memory:" () in
  Memory.store_message ~db ~session_key:"mysession" (mk_msg "user" "hi");
  let sessions = Memory.list_sessions ~db in
  Alcotest.(check int) "1 session" 1 (List.length sessions);
  Alcotest.(check string) "session key" "mysession" (List.hd sessions)

let test_list_sessions_multiple () =
  let db = Memory.init ~db_path:":memory:" () in
  Memory.store_message ~db ~session_key:"a" (mk_msg "user" "1");
  Memory.store_message ~db ~session_key:"b" (mk_msg "user" "2");
  Memory.store_message ~db ~session_key:"c" (mk_msg "user" "3");
  let sessions = Memory.list_sessions ~db in
  Alcotest.(check int) "3 sessions" 3 (List.length sessions)

let test_list_sessions_deduplicates () =
  let db = Memory.init ~db_path:":memory:" () in
  Memory.store_message ~db ~session_key:"same" (mk_msg "user" "1");
  Memory.store_message ~db ~session_key:"same" (mk_msg "assistant" "2");
  Memory.store_message ~db ~session_key:"same" (mk_msg "user" "3");
  let sessions = Memory.list_sessions ~db in
  Alcotest.(check int) "deduplicated to 1" 1 (List.length sessions)

(* --- cleanup_session tests --- *)

let test_cleanup_session_max_messages () =
  let db = Memory.init ~db_path:":memory:" () in
  for i = 1 to 10 do
    Memory.store_message ~db ~session_key:"s1"
      (mk_msg "user" (Printf.sprintf "msg%d" i))
  done;
  Memory.cleanup_session ~db ~session_key:"s1" ~max_messages:3 ~max_age_days:0;
  let msgs = Memory.load_history ~db ~session_key:"s1" in
  Alcotest.(check bool) "at most 3 messages kept" true (List.length msgs <= 3)

let test_cleanup_session_max_messages_keeps_newest () =
  let db = Memory.init ~db_path:":memory:" () in
  for i = 1 to 5 do
    Memory.store_message ~db ~session_key:"s1"
      (mk_msg "user" (Printf.sprintf "msg%d" i))
  done;
  Memory.cleanup_session ~db ~session_key:"s1" ~max_messages:2 ~max_age_days:0;
  let msgs = Memory.load_history ~db ~session_key:"s1" in
  (* Should keep the last 2: msg4, msg5 *)
  Alcotest.(check bool)
    "keeps 2 newest" true
    (List.for_all
       (fun (m : Provider.message) -> m.content = "msg4" || m.content = "msg5")
       msgs)

let test_cleanup_session_zero_max_messages_noop () =
  let db = Memory.init ~db_path:":memory:" () in
  for i = 1 to 5 do
    Memory.store_message ~db ~session_key:"s1"
      (mk_msg "user" (Printf.sprintf "msg%d" i))
  done;
  Memory.cleanup_session ~db ~session_key:"s1" ~max_messages:0 ~max_age_days:0;
  let msgs = Memory.load_history ~db ~session_key:"s1" in
  Alcotest.(check int) "all messages preserved when max=0" 5 (List.length msgs)

(* --- search tests (search_enabled=true) --- *)

let test_search_finds_matching_content () =
  let db = Memory.init ~db_path:":memory:" ~search_enabled:true () in
  Memory.store_message ~db ~session_key:"s1"
    (mk_msg "user" "OCaml is a functional language");
  Memory.store_message ~db ~session_key:"s1"
    (mk_msg "assistant" "Python is dynamic");
  let results = Memory.search ~db ~query:"OCaml" ~limit:5 () in
  Alcotest.(check bool) "found OCaml" true (List.length results > 0)

let test_search_excludes_non_matching () =
  let db = Memory.init ~db_path:":memory:" ~search_enabled:true () in
  Memory.store_message ~db ~session_key:"s1" (mk_msg "user" "hello world");
  let results = Memory.search ~db ~query:"xyznonexistent12345" ~limit:5 () in
  Alcotest.(check int) "no results for missing query" 0 (List.length results)

let test_search_respects_limit () =
  let db = Memory.init ~db_path:":memory:" ~search_enabled:true () in
  for i = 1 to 10 do
    Memory.store_message ~db ~session_key:"s1"
      (mk_msg "user" (Printf.sprintf "topic number %d" i))
  done;
  let results = Memory.search ~db ~query:"topic" ~limit:3 () in
  Alcotest.(check bool) "at most 3" true (List.length results <= 3)

let test_search_session_filter () =
  let db = Memory.init ~db_path:":memory:" ~search_enabled:true () in
  Memory.store_message ~db ~session_key:"s1" (mk_msg "user" "OCaml rocks");
  Memory.store_message ~db ~session_key:"s2" (mk_msg "user" "OCaml is great");
  let results =
    Memory.search ~db ~query:"OCaml" ~session_key:"s1" ~limit:5 ()
  in
  Alcotest.(check int) "only s1 result" 1 (List.length results)

let test_search_empty_db () =
  let db = Memory.init ~db_path:":memory:" ~search_enabled:true () in
  let results = Memory.search ~db ~query:"anything" ~limit:5 () in
  Alcotest.(check int) "empty db no results" 0 (List.length results)

(* --- cleanup_all tests --- *)

let test_cleanup_all_multiple_sessions () =
  let db = Memory.init ~db_path:":memory:" () in
  for i = 1 to 8 do
    Memory.store_message ~db ~session_key:"a"
      (mk_msg "user" (Printf.sprintf "msg%d" i))
  done;
  for i = 1 to 6 do
    Memory.store_message ~db ~session_key:"b"
      (mk_msg "user" (Printf.sprintf "msg%d" i))
  done;
  Memory.cleanup_all ~db ~max_messages:3 ~max_age_days:0;
  let a_msgs = Memory.load_history ~db ~session_key:"a" in
  let b_msgs = Memory.load_history ~db ~session_key:"b" in
  Alcotest.(check bool) "a at most 3" true (List.length a_msgs <= 3);
  Alcotest.(check bool) "b at most 3" true (List.length b_msgs <= 3)

let test_tool_result_roundtrip () =
  let db = Memory.init ~db_path:":memory:" () in
  let msg =
    Provider.make_tool_result ~tool_call_id:"tc-99" ~name:"bash_exec"
      ~content:"done"
  in
  Memory.store_message ~db ~session_key:"s1" msg;
  let msgs = Memory.load_history ~db ~session_key:"s1" in
  let m = List.hd msgs in
  Alcotest.(check string) "role is tool" "tool" m.role;
  Alcotest.(check (option string)) "tool_call_id" (Some "tc-99") m.tool_call_id;
  Alcotest.(check string) "content" "done" m.content

let suite =
  [
    Alcotest.test_case "init creates db" `Quick test_init_creates_db;
    Alcotest.test_case "init search enabled" `Quick test_init_search_enabled;
    Alcotest.test_case "init search disabled" `Quick test_init_search_disabled;
    Alcotest.test_case "init double call" `Quick test_init_double_call;
    Alcotest.test_case "store_message inserts" `Quick test_store_message_inserts;
    Alcotest.test_case "store_message role preserved" `Quick
      test_store_message_role_preserved;
    Alcotest.test_case "store_message content preserved" `Quick
      test_store_message_content_preserved;
    Alcotest.test_case "store multiple messages" `Quick
      test_store_multiple_messages;
    Alcotest.test_case "store message with tool_call_id" `Quick
      test_store_message_with_tool_call_id;
    Alcotest.test_case "store message with tool_calls" `Quick
      test_store_message_with_tool_calls;
    Alcotest.test_case "load history order" `Quick test_load_history_order;
    Alcotest.test_case "load history empty session" `Quick
      test_load_history_empty_session;
    Alcotest.test_case "load history session isolation" `Quick
      test_load_history_session_isolation;
    Alcotest.test_case "clear session" `Quick test_clear_session;
    Alcotest.test_case "clear session isolates others" `Quick
      test_clear_session_isolates_others;
    Alcotest.test_case "list sessions empty" `Quick test_list_sessions_empty;
    Alcotest.test_case "list sessions single" `Quick test_list_sessions_single;
    Alcotest.test_case "list sessions multiple" `Quick
      test_list_sessions_multiple;
    Alcotest.test_case "list sessions deduplicates" `Quick
      test_list_sessions_deduplicates;
    Alcotest.test_case "cleanup session max messages" `Quick
      test_cleanup_session_max_messages;
    Alcotest.test_case "cleanup session keeps newest" `Quick
      test_cleanup_session_max_messages_keeps_newest;
    Alcotest.test_case "cleanup session zero max noop" `Quick
      test_cleanup_session_zero_max_messages_noop;
    Alcotest.test_case "search finds matching content" `Quick
      test_search_finds_matching_content;
    Alcotest.test_case "search excludes non-matching" `Quick
      test_search_excludes_non_matching;
    Alcotest.test_case "search respects limit" `Quick test_search_respects_limit;
    Alcotest.test_case "search session filter" `Quick test_search_session_filter;
    Alcotest.test_case "search empty db" `Quick test_search_empty_db;
    Alcotest.test_case "cleanup all multiple sessions" `Quick
      test_cleanup_all_multiple_sessions;
    Alcotest.test_case "tool result roundtrip" `Quick test_tool_result_roundtrip;
  ]
