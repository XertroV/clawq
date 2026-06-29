(** Tests for Setup_room_wizard Teams-first connector path and Slack baseline.
*)

open Setup_room_wizard

let make_empty_cfg () : Runtime_config.t =
  Config_loader.parse_config (`Assoc [])

let make_teams_cfg () : Runtime_config.t =
  let json =
    Yojson.Safe.from_string
      {|{"channels": {"teams": {"app_id": "test-app", "app_secret": "secret", "tenant_id": "tenant", "webhook_path": "/webhook", "service_url": "https://smba.trafficmanager.net"}}}|}
  in
  Config_loader.parse_config json

let make_slack_cfg () : Runtime_config.t =
  let json =
    Yojson.Safe.from_string
      {|{"channels": {"slack": {"bot_token": "xoxb-test", "signing_secret": "secret", "events_path": "/slack/events", "app_token": "xapp-test", "socket_mode": true}}}|}
  in
  Config_loader.parse_config json

let make_both_cfg () : Runtime_config.t =
  let json =
    Yojson.Safe.from_string
      {|{"channels": {"teams": {"app_id": "test-app", "app_secret": "secret", "tenant_id": "tenant", "webhook_path": "/webhook", "service_url": "https://smba.trafficmanager.net"}, "slack": {"bot_token": "xoxb-test", "signing_secret": "secret", "events_path": "/slack/events", "app_token": "xapp-test", "socket_mode": true}}}|}
  in
  Config_loader.parse_config json

(** {1 Connector detection tests} *)

let test_connector_is_configured () =
  let base_cfg = make_empty_cfg () in
  (* When teams is not configured *)
  Alcotest.(check bool)
    "teams not configured" false
    (connector_is_configured base_cfg "teams");
  (* When teams IS configured *)
  let cfg_with_teams = make_teams_cfg () in
  Alcotest.(check bool)
    "teams configured" true
    (connector_is_configured cfg_with_teams "teams");
  (* Unknown connector *)
  Alcotest.(check bool)
    "unknown connector" false
    (connector_is_configured base_cfg "matrix")

let test_configured_connectors () =
  let base_cfg = make_empty_cfg () in
  Alcotest.(check (list string))
    "no connectors" []
    (configured_connectors base_cfg);
  let cfg_with_teams = make_teams_cfg () in
  Alcotest.(check bool)
    "teams in configured list" true
    (List.mem "teams" (configured_connectors cfg_with_teams))

let test_default_connector () =
  let base_cfg = make_empty_cfg () in
  (* When nothing is configured, defaults to "teams" *)
  Alcotest.(check string)
    "default with no config" "teams"
    (default_connector base_cfg);
  (* When teams is configured *)
  let cfg_with_teams = make_teams_cfg () in
  Alcotest.(check string)
    "default with teams" "teams"
    (default_connector cfg_with_teams);
  (* When only slack is configured *)
  let cfg_with_slack = make_slack_cfg () in
  Alcotest.(check string)
    "default with slack only" "slack"
    (default_connector cfg_with_slack)

(** {1 Room validation tests} *)

let test_validate_teams_room_id () =
  Alcotest.(check bool)
    "empty teams room is error" true
    (Result.is_error (validate_teams_room_id ""));
  Alcotest.(check bool)
    "short teams room is error" true
    (Result.is_error (validate_teams_room_id "ab"));
  Alcotest.(check bool)
    "non-teams format is error" true
    (Result.is_error (validate_teams_room_id "invalid"));
  Alcotest.(check bool)
    "random colon format is error" true
    (Result.is_error (validate_teams_room_id "abc:def"));
  Alcotest.(check bool)
    "valid teams room with thread" true
    (Result.is_ok (validate_teams_room_id "19:abc123@thread.tacv2"));
  Alcotest.(check bool)
    "valid teams room 19: prefix" true
    (Result.is_ok (validate_teams_room_id "19:abc123"))

let test_validate_slack_room_id () =
  Alcotest.(check bool)
    "empty slack room is error" true
    (Result.is_error (validate_slack_room_id ""));
  Alcotest.(check bool)
    "short slack room is error" true
    (Result.is_error (validate_slack_room_id "X"));
  Alcotest.(check bool)
    "valid slack public channel" true
    (Result.is_ok (validate_slack_room_id "C12345"));
  Alcotest.(check bool)
    "valid slack private channel" true
    (Result.is_ok (validate_slack_room_id "G67890"));
  Alcotest.(check bool)
    "valid slack dm" true
    (Result.is_ok (validate_slack_room_id "D12345"));
  Alcotest.(check bool)
    "valid slack channel name" true
    (Result.is_ok (validate_slack_room_id "#general"));
  Alcotest.(check bool)
    "invalid slack room" true
    (Result.is_error (validate_slack_room_id "invalid-id"))

let test_validate_room_id_for_connector () =
  Alcotest.(check bool)
    "teams dispatcher ok" true
    (Result.is_ok
       (validate_room_id_for_connector "teams" "19:abc@thread.tacv2"));
  Alcotest.(check bool)
    "slack dispatcher ok" true
    (Result.is_ok (validate_room_id_for_connector "slack" "C12345"));
  Alcotest.(check bool)
    "other connector empty is error" true
    (Result.is_error (validate_room_id_for_connector "discord" ""));
  Alcotest.(check bool)
    "other connector valid" true
    (Result.is_ok (validate_room_id_for_connector "discord" "room-123"))

(** {1 Capability comparison tests} *)

let test_compare_teams_vs_slack () =
  let rows = compare_teams_vs_slack () in
  Alcotest.(check int) "comparison row count" 11 (List.length rows);
  (* Check that Teams has cards *)
  let cards_row = List.find (fun r -> r.feature = "Adaptive Cards") rows in
  Alcotest.(check string) "teams has cards" "Yes" cards_row.teams_value;
  Alcotest.(check string) "slack no cards" "No" cards_row.slack_value;
  (* Check that Slack has reactions *)
  let react_row = List.find (fun r -> r.feature = "Reactions") rows in
  Alcotest.(check string) "slack has reactions" "Yes" react_row.slack_value;
  Alcotest.(check string) "teams no reactions" "No" react_row.teams_value;
  (* Check max message length *)
  let length_row = List.find (fun r -> r.feature = "Max message length") rows in
  Alcotest.(check string) "teams max length" "28672" length_row.teams_value;
  Alcotest.(check string) "slack max length" "4000" length_row.slack_value

(** {1 Plan generation with connector_type tests} *)

let test_plan_includes_connector () =
  let cfg = make_empty_cfg () in
  let state =
    {
      default_state with
      profile_id = "test-profile";
      connector_type = "teams";
      connector_room = "19:abc@thread.tacv2";
    }
  in
  let plan = generate_plan ~cfg ~state in
  let connector_items = List.filter (fun p -> p.category = "Connector") plan in
  Alcotest.(check int) "has connector item" 1 (List.length connector_items);
  let item = List.hd connector_items in
  Alcotest.(check string) "teams primary" "primary" item.action

let test_plan_slack_connector () =
  let cfg = make_empty_cfg () in
  let state =
    {
      default_state with
      profile_id = "test-profile";
      connector_type = "slack";
      connector_room = "C12345";
    }
  in
  let plan = generate_plan ~cfg ~state in
  let connector_items = List.filter (fun p -> p.category = "Connector") plan in
  Alcotest.(check int) "has connector item" 1 (List.length connector_items);
  let item = List.hd connector_items in
  Alcotest.(check string) "slack bind" "bind" item.action

(** {1 Readiness check tests} *)

let test_readiness_connector_available () =
  let base_cfg = make_empty_cfg () in
  let state =
    { default_state with connector_type = "teams"; connector_room = "19:abc" }
  in
  let checks = run_readiness_checks ~cfg:base_cfg ~state in
  let connector_check =
    List.find (fun c -> c.name = "Connector Available") checks
  in
  Alcotest.(check bool) "teams not available" false connector_check.passed;
  (* Now with teams configured *)
  let cfg_with_teams = make_teams_cfg () in
  let checks2 = run_readiness_checks ~cfg:cfg_with_teams ~state in
  let connector_check2 =
    List.find (fun c -> c.name = "Connector Available") checks2
  in
  Alcotest.(check bool) "teams available" true connector_check2.passed

let test_readiness_room_validation () =
  let cfg = make_empty_cfg () in
  (* Valid teams room *)
  let state_valid =
    {
      default_state with
      connector_type = "teams";
      connector_room = "19:abc@thread.tacv2";
    }
  in
  let checks = run_readiness_checks ~cfg ~state:state_valid in
  let room_check = List.find (fun c -> c.name = "Connector Room") checks in
  Alcotest.(check bool) "valid teams room passes" true room_check.passed;
  (* Invalid slack room (doesn't start with C/G/D/#) *)
  let state_invalid =
    { default_state with connector_type = "slack"; connector_room = "invalid" }
  in
  let checks2 = run_readiness_checks ~cfg ~state:state_invalid in
  let room_check2 = List.find (fun c -> c.name = "Connector Room") checks2 in
  Alcotest.(check bool) "invalid slack room fails" false room_check2.passed

(** {1 Default state tests} *)

let test_default_state_is_teams () =
  Alcotest.(check string)
    "default connector type" "teams" default_state.connector_type

(** {1 Suite} *)

let suite =
  [
    Alcotest.test_case "connector_is_configured" `Quick
      test_connector_is_configured;
    Alcotest.test_case "configured_connectors" `Quick test_configured_connectors;
    Alcotest.test_case "default_connector" `Quick test_default_connector;
    Alcotest.test_case "validate_teams_room_id" `Quick
      test_validate_teams_room_id;
    Alcotest.test_case "validate_slack_room_id" `Quick
      test_validate_slack_room_id;
    Alcotest.test_case "validate_room_id_for_connector" `Quick
      test_validate_room_id_for_connector;
    Alcotest.test_case "compare_teams_vs_slack" `Quick
      test_compare_teams_vs_slack;
    Alcotest.test_case "plan_includes_connector" `Quick
      test_plan_includes_connector;
    Alcotest.test_case "plan_slack_connector" `Quick test_plan_slack_connector;
    Alcotest.test_case "connector_available" `Quick
      test_readiness_connector_available;
    Alcotest.test_case "room_validation" `Quick test_readiness_room_validation;
    Alcotest.test_case "default_state_is_teams" `Quick
      test_default_state_is_teams;
  ]
