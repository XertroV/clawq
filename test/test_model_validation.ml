(* Tests for Model_validation — the safety net that prevents bad model
   switches from bricking sessions (B600).

   The live test_completion path needs HTTP, so we only exercise the
   preflight + plumbing in unit tests. Live integration is verified by the
   daemon log when a real switch happens. *)

let make_config_with_providers providers : Runtime_config.t =
  { Runtime_config.default with providers }

let make_provider ?(api_key = "") ?(kind = None) () :
    Runtime_config.provider_config =
  { Runtime_config.default_provider_config with api_key; kind }

(* --- Preflight checks --- *)

let test_preflight_unknown_provider () =
  let config = make_config_with_providers [] in
  match Model_validation.preflight ~config ~model:"some-unknown:foo" with
  | None -> Alcotest.fail "expected error when provider not configured"
  | Some msg ->
      let ok = String.length msg > 0 in
      Alcotest.(check bool) "got non-empty error message" true ok;
      let has_provider_name =
        try
          let _ = Str.search_forward (Str.regexp_string "some-unknown") msg 0 in
          true
        with Not_found -> false
      in
      Alcotest.(check bool)
        "error mentions the offending provider name" true has_provider_name

let test_preflight_missing_api_key () =
  let providers = [ ("anthropic", make_provider ~api_key:"" ()) ] in
  let config = make_config_with_providers providers in
  match
    Model_validation.preflight ~config ~model:"anthropic:claude-sonnet-4-6"
  with
  | None -> Alcotest.fail "expected error when api_key missing"
  | Some msg ->
      let has_auth_hint =
        try
          let _ = Str.search_forward (Str.regexp_string "auth") msg 0 in
          true
        with Not_found -> false
      in
      Alcotest.(check bool) "error mentions auth" true has_auth_hint

let test_preflight_passes_with_valid_provider () =
  let providers =
    [ ("anthropic", make_provider ~api_key:"sk-test-1234567890" ()) ]
  in
  let config = make_config_with_providers providers in
  match
    Model_validation.preflight ~config ~model:"anthropic:claude-sonnet-4-6"
  with
  | None -> () (* expected — preflight passes, live test would run *)
  | Some msg -> Alcotest.failf "expected preflight to pass, got: %s" msg

let test_preflight_skips_for_plain_name () =
  (* Plain names (no provider:) can't be preflighted by provider lookup,
     so preflight returns None and the live test handles validation. *)
  let config = make_config_with_providers [] in
  match Model_validation.preflight ~config ~model:"gpt-5.4" with
  | None -> ()
  | Some msg ->
      Alcotest.failf "expected preflight to pass-through plain name, got: %s"
        msg

(* --- make_test_config preserves config except primary_model --- *)

let test_make_test_config_overrides_primary_model () =
  let config = Runtime_config.default in
  let test_cfg =
    Model_validation.make_test_config ~config ~model:"anthropic:claude-foo"
  in
  Alcotest.(check string)
    "primary_model overridden" "anthropic:claude-foo"
    test_cfg.agent_defaults.primary_model

let test_make_test_config_preserves_other_fields () =
  let config = Runtime_config.default in
  let test_cfg = Model_validation.make_test_config ~config ~model:"x:y" in
  Alcotest.(check int)
    "max_tool_iterations preserved" config.agent_defaults.max_tool_iterations
    test_cfg.agent_defaults.max_tool_iterations;
  Alcotest.(check (list (pair string string)))
    "providers list preserved (assoc keys)"
    (List.map (fun (k, _) -> (k, "")) config.providers)
    (List.map (fun (k, _) -> (k, "")) test_cfg.providers)

(* --- Format failure produces actionable output --- *)

let test_format_failure_includes_rollback () =
  let msg =
    Model_validation.format_failure ~rollback_cmd:"clawq models set-default foo"
      "connection refused"
  in
  let has_rollback =
    try
      let _ =
        Str.search_forward
          (Str.regexp_string "clawq models set-default foo")
          msg 0
      in
      true
    with Not_found -> false
  in
  Alcotest.(check bool) "rollback command appears verbatim" true has_rollback;
  let has_previous_intact =
    try
      let _ = Str.search_forward (Str.regexp_string "Previous model") msg 0 in
      true
    with Not_found -> false
  in
  Alcotest.(check bool)
    "mentions previous model is intact" true has_previous_intact

(* --- validate with unreachable provider triggers error quickly --- *)

let test_validate_unknown_provider_returns_error () =
  let config = make_config_with_providers [] in
  match
    Model_validation.validate_sync ~config ~model:"nonsense-provider:foo"
      ~timeout_s:1.0 ()
  with
  | Model_validation.Ok_validated ->
      Alcotest.fail "expected validation to fail for unknown provider"
  | Model_validation.Error_msg msg ->
      let mentions_provider =
        try
          let _ =
            Str.search_forward (Str.regexp_string "nonsense-provider") msg 0
          in
          true
        with Not_found -> false
      in
      Alcotest.(check bool)
        "error message mentions unknown provider" true mentions_provider

let suite =
  [
    Alcotest.test_case "preflight rejects unknown provider" `Quick
      test_preflight_unknown_provider;
    Alcotest.test_case "preflight rejects missing api_key" `Quick
      test_preflight_missing_api_key;
    Alcotest.test_case "preflight passes for configured provider with key"
      `Quick test_preflight_passes_with_valid_provider;
    Alcotest.test_case "preflight passes through plain names" `Quick
      test_preflight_skips_for_plain_name;
    Alcotest.test_case "make_test_config overrides primary_model" `Quick
      test_make_test_config_overrides_primary_model;
    Alcotest.test_case "make_test_config preserves other fields" `Quick
      test_make_test_config_preserves_other_fields;
    Alcotest.test_case "format_failure includes rollback command" `Quick
      test_format_failure_includes_rollback;
    Alcotest.test_case "validate returns Error_msg for unknown provider" `Quick
      test_validate_unknown_provider_returns_error;
  ]
