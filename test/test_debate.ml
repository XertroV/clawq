let with_db f =
  Test_helpers.with_memory_db (fun db ->
      Debate.init_schema db;
      f db)

(* ── build_judge_prompt tests ─────────────────────────────────────────── *)

let test_build_judge_prompt_structure () =
  let responses =
    [
      {
        Debate.model = "openai-codex:gpt-5.4";
        content = "Answer A";
        usage = Some (100, 50);
        elapsed_s = 1.2;
      };
      {
        Debate.model = "anthropic:claude-opus-4-6";
        content = "Answer B";
        usage = Some (120, 60);
        elapsed_s = 2.0;
      };
    ]
  in
  let prompt = Debate.build_judge_prompt ~prompt:"Test question" ~responses in
  Alcotest.(check bool)
    "contains original prompt" true
    (String_util.contains prompt "Test question");
  Alcotest.(check bool)
    "contains model A" true
    (String_util.contains prompt "openai-codex:gpt-5.4");
  Alcotest.(check bool)
    "contains model B" true
    (String_util.contains prompt "anthropic:claude-opus-4-6");
  Alcotest.(check bool)
    "contains Answer A" true
    (String_util.contains prompt "Answer A");
  Alcotest.(check bool)
    "contains Answer B" true
    (String_util.contains prompt "Answer B");
  Alcotest.(check bool)
    "requests JSON" true
    (String_util.contains prompt "JSON")

let test_build_judge_prompt_single_response () =
  let responses =
    [
      {
        Debate.model = "m1";
        content = "Only answer";
        usage = None;
        elapsed_s = 0.5;
      };
    ]
  in
  let prompt = Debate.build_judge_prompt ~prompt:"Q" ~responses in
  Alcotest.(check bool)
    "contains response" true
    (String_util.contains prompt "Only answer")

(* ── parse_judge_response tests ───────────────────────────────────────── *)

let test_parse_valid_json () =
  let raw =
    {|{"synthesis": "Combined answer", "confidence": 85, "agreements": ["Point A"], "disagreements": ["Point B"], "per_model": [{"model": "m1", "assessment": "Good"}]}|}
  in
  let jr = Debate.parse_judge_response raw in
  Alcotest.(check string) "synthesis" "Combined answer" jr.synthesis;
  Alcotest.(check int) "confidence" 85 jr.confidence;
  Alcotest.(check int) "agreements count" 1 (List.length jr.agreements);
  Alcotest.(check int) "disagreements count" 1 (List.length jr.disagreements);
  Alcotest.(check int) "per_model count" 1 (List.length jr.per_model);
  Alcotest.(check string) "per_model[0].model" "m1" (List.hd jr.per_model).model

let test_parse_malformed_json () =
  let raw = "This is not JSON at all" in
  let jr = Debate.parse_judge_response raw in
  Alcotest.(check string) "synthesis fallback" raw jr.synthesis;
  Alcotest.(check int) "confidence fallback" 0 jr.confidence;
  Alcotest.(check int) "agreements empty" 0 (List.length jr.agreements)

let test_parse_markdown_fenced_json () =
  let raw =
    "```json\n\
     {\"synthesis\": \"Fenced answer\", \"confidence\": 72, \"agreements\": \
     [], \"disagreements\": [], \"per_model\": []}\n\
     ```"
  in
  let jr = Debate.parse_judge_response raw in
  Alcotest.(check string) "synthesis" "Fenced answer" jr.synthesis;
  Alcotest.(check int) "confidence" 72 jr.confidence

let test_parse_empty_input () =
  let jr = Debate.parse_judge_response "" in
  Alcotest.(check string) "synthesis fallback" "" jr.synthesis;
  Alcotest.(check int) "confidence fallback" 0 jr.confidence

(* ── format tests ─────────────────────────────────────────────────────── *)

let mock_result ?(judge = None) ?(judge_model_used = None) () =
  {
    Debate.prompt = "Test prompt";
    models_queried = [ "m1"; "m2" ];
    responses =
      [
        Ok
          {
            Debate.model = "m1";
            content = "Response 1";
            usage = Some (100, 50);
            elapsed_s = 1.0;
          };
        Ok
          {
            Debate.model = "m2";
            content = "Response 2";
            usage = Some (200, 100);
            elapsed_s = 2.0;
          };
      ];
    judge;
    judge_model_used;
    total_cost_usd = 0.05;
    started_at = 0.0;
    elapsed_s = 3.5;
  }

let mock_judge =
  {
    Debate.synthesis = "Synthesis text";
    confidence = 90;
    agreements = [ "Both agree on X" ];
    disagreements = [ "They differ on Y" ];
    per_model =
      [
        { Debate.model = "m1"; assessment = "Strong on X" };
        { Debate.model = "m2"; assessment = "Strong on Y" };
      ];
    raw_judge_response = "raw";
  }

let test_format_text_with_judge () =
  let result = mock_result ~judge:(Some mock_judge) () in
  let text = Debate.format_text result in
  Alcotest.(check bool)
    "contains synthesis" true
    (String_util.contains text "Synthesis text");
  Alcotest.(check bool)
    "contains confidence" true
    (String_util.contains text "90/100");
  Alcotest.(check bool)
    "contains agreement" true
    (String_util.contains text "Both agree on X");
  Alcotest.(check bool)
    "contains disagreement" true
    (String_util.contains text "They differ on Y")

let test_format_text_without_judge () =
  let result = mock_result () in
  let text = Debate.format_text result in
  Alcotest.(check bool)
    "contains responses header" true
    (String_util.contains text "Individual Responses");
  Alcotest.(check bool) "contains m1" true (String_util.contains text "m1")

let test_format_json () =
  let result = mock_result ~judge:(Some mock_judge) () in
  let json_str = Debate.format_json result in
  let json = Yojson.Safe.from_string json_str in
  let open Yojson.Safe.Util in
  Alcotest.(check string)
    "prompt" "Test prompt"
    (json |> member "prompt" |> to_string);
  Alcotest.(check int)
    "models count" 2
    (json |> member "models_queried" |> to_list |> List.length);
  let judge_json = json |> member "judge" in
  Alcotest.(check int)
    "judge confidence" 90
    (judge_json |> member "confidence" |> to_int)

let test_format_json_no_judge () =
  let result = mock_result () in
  let json_str = Debate.format_json result in
  let json = Yojson.Safe.from_string json_str in
  let open Yojson.Safe.Util in
  Alcotest.(check bool) "judge is null" true (json |> member "judge" = `Null)

(* ── DB tests ─────────────────────────────────────────────────────────── *)

let test_db_init_schema () = with_db (fun _db -> ())

let test_db_insert_and_list () =
  with_db (fun db ->
      let result = mock_result ~judge:(Some mock_judge) () in
      Debate.insert_debate_round ~db ~result;
      let rounds = Debate.list_debate_rounds ~db ~limit:10 in
      Alcotest.(check int) "1 round" 1 (List.length rounds);
      let r = List.hd rounds in
      Alcotest.(check bool)
        "prompt contains" true
        (String_util.contains r.prompt "Test prompt");
      Alcotest.(check (option int)) "confidence" (Some 90) r.confidence)

let test_db_insert_and_get () =
  with_db (fun db ->
      let result = mock_result ~judge:(Some mock_judge) () in
      Debate.insert_debate_round ~db ~result;
      let rounds = Debate.list_debate_rounds ~db ~limit:10 in
      let id = (List.hd rounds).id in
      match Debate.get_debate_round ~db ~id with
      | None -> Alcotest.fail "round not found"
      | Some r ->
          Alcotest.(check string) "full prompt" "Test prompt" r.prompt;
          Alcotest.(check (option int)) "confidence" (Some 90) r.confidence;
          Alcotest.(check bool)
            "has judge result" true
            (r.judge_result_json <> None))

let test_db_get_nonexistent () =
  with_db (fun db ->
      Alcotest.(check bool)
        "returns None" true
        (Debate.get_debate_round ~db ~id:999 = None))

let test_db_list_empty () =
  with_db (fun db ->
      let rounds = Debate.list_debate_rounds ~db ~limit:10 in
      Alcotest.(check int) "0 rounds" 0 (List.length rounds))

(* ── CLI arg parsing tests ────────────────────────────────────────────── *)

let test_parse_args_basic () =
  let cli = Debate.parse_args [ "Hello"; "world" ] in
  Alcotest.(check string) "prompt" "Hello world" cli.prompt;
  Alcotest.(check bool) "no models" true (cli.models = None);
  Alcotest.(check bool) "no judge" true (cli.judge = None);
  Alcotest.(check bool) "not no_judge" false cli.no_judge;
  Alcotest.(check bool) "not history" false cli.history

let test_parse_args_models () =
  let cli = Debate.parse_args [ "--models"; "m1,m2,m3"; "prompt" ] in
  Alcotest.(check string) "prompt" "prompt" cli.prompt;
  match cli.models with
  | None -> Alcotest.fail "expected models"
  | Some ms -> Alcotest.(check int) "3 models" 3 (List.length ms)

let test_parse_args_judge () =
  let cli = Debate.parse_args [ "--judge"; "my_judge"; "prompt" ] in
  Alcotest.(check (option string)) "judge" (Some "my_judge") cli.judge

let test_parse_args_format_json () =
  let cli = Debate.parse_args [ "--format"; "json"; "prompt" ] in
  Alcotest.(check bool) "json format" true (cli.format = `Json)

let test_parse_args_no_judge () =
  let cli = Debate.parse_args [ "--no-judge"; "prompt" ] in
  Alcotest.(check bool) "no_judge" true cli.no_judge

let test_parse_args_history () =
  let cli = Debate.parse_args [ "--history" ] in
  Alcotest.(check bool) "history" true cli.history

let test_parse_args_show () =
  let cli = Debate.parse_args [ "--show"; "42" ] in
  Alcotest.(check (option int)) "show_id" (Some 42) cli.show_id

(* ── Config defaults tests ────────────────────────────────────────────── *)

let test_config_defaults () =
  let def = Runtime_config.default_debate_config in
  Alcotest.(check bool) "enabled" true def.enabled;
  Alcotest.(check int) "3 default models" 3 (List.length def.default_models);
  Alcotest.(check string)
    "judge model" "anthropic:claude-opus-4-6" def.judge_model;
  Alcotest.(check int) "max_parallel" 5 def.max_parallel

(* ── Error scenario formatting ────────────────────────────────────────── *)

let test_format_all_failed () =
  let result =
    {
      Debate.prompt = "Test";
      models_queried = [ "m1"; "m2" ];
      responses = [ Error "m1 failed"; Error "m2 failed" ];
      judge = None;
      judge_model_used = None;
      total_cost_usd = 0.0;
      started_at = 0.0;
      elapsed_s = 1.0;
    }
  in
  let text = Debate.format_text result in
  Alcotest.(check bool)
    "contains FAILED" true
    (String_util.contains text "FAILED")

let test_format_partial_success () =
  let result =
    {
      Debate.prompt = "Test";
      models_queried = [ "m1"; "m2" ];
      responses =
        [
          Ok
            {
              Debate.model = "m1";
              content = "Answer";
              usage = None;
              elapsed_s = 1.0;
            };
          Error "m2 failed";
        ];
      judge = None;
      judge_model_used = None;
      total_cost_usd = 0.0;
      started_at = 0.0;
      elapsed_s = 1.0;
    }
  in
  let text = Debate.format_text result in
  Alcotest.(check bool)
    "contains m1 answer" true
    (String_util.contains text "Answer");
  Alcotest.(check bool)
    "contains m2 failure" true
    (String_util.contains text "m2 failed")

let test_format_history_list_empty () =
  let text = Debate.format_history_list [] in
  Alcotest.(check string) "empty message" "No debate rounds found." text

let test_format_history_list_nonempty () =
  let rounds =
    [
      {
        Debate.id = 1;
        prompt = "test prompt";
        models_json = "[\"m1\"]";
        confidence = Some 85;
        total_cost_usd = 0.01;
        elapsed_s = 2.0;
        created_at = "2026-01-01 00:00:00";
      };
    ]
  in
  let text = Debate.format_history_list rounds in
  Alcotest.(check bool) "contains ID" true (String_util.contains text "1");
  Alcotest.(check bool)
    "contains confidence" true
    (String_util.contains text "85/100")

(* ── Empty prompt rejection ───────────────────────────────────────────── *)

let test_empty_prompt_shows_usage () =
  let output =
    Debate.cmd_debate
      ~get_config:(fun () -> Runtime_config.default)
      ~get_db:(fun () -> Sqlite3.db_open ":memory:")
      []
  in
  Alcotest.(check bool)
    "shows usage" true
    (String_util.contains output "Usage:")

(* ── Suite ─────────────────────────────────────────────────────────────── *)

let suite =
  [
    Alcotest.test_case "build_judge_prompt structure" `Quick
      test_build_judge_prompt_structure;
    Alcotest.test_case "build_judge_prompt single response" `Quick
      test_build_judge_prompt_single_response;
    Alcotest.test_case "parse valid JSON" `Quick test_parse_valid_json;
    Alcotest.test_case "parse malformed JSON" `Quick test_parse_malformed_json;
    Alcotest.test_case "parse markdown-fenced JSON" `Quick
      test_parse_markdown_fenced_json;
    Alcotest.test_case "parse empty input" `Quick test_parse_empty_input;
    Alcotest.test_case "format text with judge" `Quick
      test_format_text_with_judge;
    Alcotest.test_case "format text without judge" `Quick
      test_format_text_without_judge;
    Alcotest.test_case "format json with judge" `Quick test_format_json;
    Alcotest.test_case "format json no judge" `Quick test_format_json_no_judge;
    Alcotest.test_case "db init schema" `Quick test_db_init_schema;
    Alcotest.test_case "db insert and list" `Quick test_db_insert_and_list;
    Alcotest.test_case "db insert and get" `Quick test_db_insert_and_get;
    Alcotest.test_case "db get nonexistent" `Quick test_db_get_nonexistent;
    Alcotest.test_case "db list empty" `Quick test_db_list_empty;
    Alcotest.test_case "parse args basic" `Quick test_parse_args_basic;
    Alcotest.test_case "parse args models" `Quick test_parse_args_models;
    Alcotest.test_case "parse args judge" `Quick test_parse_args_judge;
    Alcotest.test_case "parse args format json" `Quick
      test_parse_args_format_json;
    Alcotest.test_case "parse args no-judge" `Quick test_parse_args_no_judge;
    Alcotest.test_case "parse args history" `Quick test_parse_args_history;
    Alcotest.test_case "parse args show" `Quick test_parse_args_show;
    Alcotest.test_case "config defaults" `Quick test_config_defaults;
    Alcotest.test_case "format all failed" `Quick test_format_all_failed;
    Alcotest.test_case "format partial success" `Quick
      test_format_partial_success;
    Alcotest.test_case "format history list empty" `Quick
      test_format_history_list_empty;
    Alcotest.test_case "format history list nonempty" `Quick
      test_format_history_list_nonempty;
    Alcotest.test_case "empty prompt shows usage" `Quick
      test_empty_prompt_shows_usage;
  ]
