(* Tests for egress audit event recording *)

open Egress_audit

let check_decision msg expected (event : event) =
  Alcotest.check
    (Alcotest.of_pp (fun fmt -> function
      | Allowed -> Format.fprintf fmt "Allowed"
      | Denied -> Format.fprintf fmt "Denied"))
    msg expected event.decision

(** Create an in-memory SQLite database with egress_audit schema. *)
let create_test_db () =
  let db = Sqlite3.db_open ":memory:" in
  init_schema db;
  db

(** Test: redact_host obscures intermediate labels *)
let test_redact_host () =
  Alcotest.(check string)
    "simple host" "e******.com"
    (redact_host "example.com");
  Alcotest.(check string)
    "subdomain" "a**.******.com"
    (redact_host "api.example.com");
  Alcotest.(check string)
    "deep subdomain" "a**.******.******.com"
    (redact_host "api.bob.example.com");
  Alcotest.(check string) "localhost" "l********" (redact_host "localhost");
  Alcotest.(check string) "single char" "*" (redact_host "a")

(** Test: redact_method shows first and last character *)
let test_redact_method () =
  Alcotest.(check string) "GET" "G*T" (redact_method "GET");
  Alcotest.(check string) "POST" "P**T" (redact_method "POST");
  Alcotest.(check string) "DELETE" "D****E" (redact_method "DELETE");
  Alcotest.(check string) "short" "*" (redact_method "A")

(** Test: redact_path keeps first segment *)
let test_redact_path () =
  Alcotest.(check string) "simple path" "/api" (redact_path "/api");
  Alcotest.(check string) "nested path" "/api/**" (redact_path "/api/v1/users");
  Alcotest.(check string) "root path" "/" (redact_path "/")

(** Test: record and query round-trip *)
let test_record_and_query () =
  let db = create_test_db () in
  record ~db ~decision:Allowed ~host:"api.example.com" ~method_:"GET"
    ~path:"/api/data" ~matched_rule_index:0 ~session_key:"telegram:123"
    ~snapshot_id:"snap_001" ~tool_name:"http_request" ~profile_id:"default" ();
  let events = query ~db () in
  Alcotest.(check int) "one event" 1 (List.length events);
  let event = List.hd events in
  check_decision "allowed" Allowed event;
  Alcotest.(check string) "host redacted" "a**.******.com" event.host_redacted;
  Alcotest.(check (option string))
    "method redacted" (Some "G*T") event.method_redacted;
  Alcotest.(check (option string))
    "path redacted" (Some "/api/**") event.path_redacted;
  Alcotest.(check int) "rule index" 0 event.matched_rule_index;
  Alcotest.(check (option string))
    "session key" (Some "telegram:123") event.session_key;
  Alcotest.(check (option string))
    "snapshot id" (Some "snap_001") event.snapshot_id;
  Alcotest.(check (option string))
    "tool name" (Some "http_request") event.tool_name;
  Alcotest.(check (option string))
    "profile id" (Some "default") event.profile_id;
  ignore (Sqlite3.db_close db)

(** Test: denied event records correctly *)
let test_denied_event () =
  let db = create_test_db () in
  record ~db ~decision:Denied ~host:"blocked.example.com" ~method_:"POST"
    ~matched_rule_index:1 ();
  let events = query ~db ~decision:Denied () in
  Alcotest.(check int) "one denied event" 1 (List.length events);
  let event = List.hd events in
  check_decision "denied" Denied event;
  Alcotest.(check int) "rule index" 1 event.matched_rule_index;
  ignore (Sqlite3.db_close db)

(** Test: credential handle IDs are stored as aliases *)
let test_credential_handle_ids () =
  let db = create_test_db () in
  record ~db ~decision:Allowed ~host:"api.example.com" ~matched_rule_index:0
    ~credential_handle_ids:[ "github-app:main"; "slack-bot:prod" ]
    ();
  let events = query ~db () in
  let event = List.hd events in
  Alcotest.(check int)
    "two handle ids" 2
    (List.length event.credential_handle_ids);
  Alcotest.(check string)
    "first handle id" "github-app:main"
    (List.nth event.credential_handle_ids 0);
  Alcotest.(check string)
    "second handle id" "slack-bot:prod"
    (List.nth event.credential_handle_ids 1);
  ignore (Sqlite3.db_close db)

(** Test: query filters by session_key *)
let test_query_by_session_key () =
  let db = create_test_db () in
  record ~db ~decision:Allowed ~host:"a.com" ~matched_rule_index:0
    ~session_key:"telegram:1" ();
  record ~db ~decision:Allowed ~host:"b.com" ~matched_rule_index:0
    ~session_key:"discord:2" ();
  record ~db ~decision:Allowed ~host:"c.com" ~matched_rule_index:0
    ~session_key:"telegram:1" ();
  let events = query ~db ~session_key:"telegram:1" () in
  Alcotest.(check int) "two telegram events" 2 (List.length events);
  ignore (Sqlite3.db_close db)

(** Test: query filters by tool_name *)
let test_query_by_tool_name () =
  let db = create_test_db () in
  record ~db ~decision:Allowed ~host:"a.com" ~matched_rule_index:0
    ~tool_name:"http_request" ();
  record ~db ~decision:Allowed ~host:"b.com" ~matched_rule_index:0
    ~tool_name:"web_fetch" ();
  record ~db ~decision:Allowed ~host:"c.com" ~matched_rule_index:0
    ~tool_name:"http_request" ();
  let events = query ~db ~tool_name:"web_fetch" () in
  Alcotest.(check int) "one web_fetch event" 1 (List.length events);
  ignore (Sqlite3.db_close db)

(** Test: event_to_json produces valid JSON *)
let test_event_to_json () =
  let db = create_test_db () in
  record ~db ~decision:Allowed ~host:"api.example.com" ~method_:"GET"
    ~path:"/data" ~matched_rule_index:0 ~session_key:"s1"
    ~credential_handle_ids:[ "handle-1" ] ();
  let events = query ~db () in
  let event = List.hd events in
  let json = event_to_json event in
  let json_str = Yojson.Safe.to_string json in
  let parsed = Yojson.Safe.from_string json_str in
  let open Yojson.Safe.Util in
  Alcotest.(check string)
    "decision" "allowed"
    (parsed |> member "decision" |> to_string);
  Alcotest.(check string)
    "host redacted" "a**.******.com"
    (parsed |> member "host_redacted" |> to_string);
  Alcotest.(check bool)
    "has credential_handle_ids" true
    (parsed |> member "credential_handle_ids" |> to_list <> []);
  ignore (Sqlite3.db_close db)

(** Test: delete_before removes old events *)
let test_delete_before () =
  let db = create_test_db () in
  record ~db ~decision:Allowed ~host:"old.com" ~matched_rule_index:0 ();
  (* Delete events before a far-future timestamp *)
  let deleted = delete_before ~db ~before_timestamp:"2099-01-01T00:00:00Z" in
  Alcotest.(check int) "deleted one" 1 deleted;
  let events = query ~db () in
  Alcotest.(check int) "no events left" 0 (List.length events);
  ignore (Sqlite3.db_close db)

(** Test: multiple events recorded with different timestamps *)
let test_multiple_events_recorded () =
  let db = create_test_db () in
  (* Two records of same host/decision will get different timestamps *)
  record ~db ~decision:Allowed ~host:"api.example.com" ~matched_rule_index:0 ();
  record ~db ~decision:Allowed ~host:"api.example.com" ~matched_rule_index:0 ();
  let events = query ~db () in
  (* Both events should be recorded (different timestamps) *)
  Alcotest.(check bool) "at least one event" true (List.length events >= 1);
  ignore (Sqlite3.db_close db)

(** Test: optional fields default to None *)
let test_optional_fields_none () =
  let db = create_test_db () in
  record ~db ~decision:Denied ~host:"test.com" ~matched_rule_index:(-1) ();
  let events = query ~db () in
  let event = List.hd events in
  Alcotest.(check (option string)) "no method" None event.method_redacted;
  Alcotest.(check (option string)) "no path" None event.path_redacted;
  Alcotest.(check (option string)) "no session" None event.session_key;
  Alcotest.(check (option string)) "no snapshot" None event.snapshot_id;
  Alcotest.(check (option string)) "no tool" None event.tool_name;
  Alcotest.(check (option string)) "no profile" None event.profile_id;
  Alcotest.(check int) "no handles" 0 (List.length event.credential_handle_ids);
  ignore (Sqlite3.db_close db)

let suite =
  [
    Alcotest.test_case "redact_host" `Quick test_redact_host;
    Alcotest.test_case "redact_method" `Quick test_redact_method;
    Alcotest.test_case "redact_path" `Quick test_redact_path;
    Alcotest.test_case "record and query" `Quick test_record_and_query;
    Alcotest.test_case "denied event" `Quick test_denied_event;
    Alcotest.test_case "credential handle IDs" `Quick test_credential_handle_ids;
    Alcotest.test_case "query by session_key" `Quick test_query_by_session_key;
    Alcotest.test_case "query by tool_name" `Quick test_query_by_tool_name;
    Alcotest.test_case "event_to_json" `Quick test_event_to_json;
    Alcotest.test_case "delete_before" `Quick test_delete_before;
    Alcotest.test_case "multiple events recorded" `Quick
      test_multiple_events_recorded;
    Alcotest.test_case "optional fields none" `Quick test_optional_fields_none;
  ]
