let test_default_path_uses_home () =
  Test_helpers.with_temp_home (fun home ->
      let expected = Filename.concat home ".clawq" in
      let actual = Dot_dir.path () in
      Alcotest.(check string) "default path" expected actual)

let test_env_var_overrides_home () =
  Test_helpers.with_temp_home (fun _home ->
      let custom =
        Filename.concat (Filename.get_temp_dir_name ()) "clawq_custom_test"
      in
      let old = Sys.getenv_opt Dot_dir.env_var in
      Unix.putenv Dot_dir.env_var custom;
      Fun.protect
        (fun () ->
          let actual = Dot_dir.path () in
          Alcotest.(check string) "env override" custom actual)
        ~finally:(fun () ->
          match old with
          | Some v -> Unix.putenv Dot_dir.env_var v
          | None -> Unix.putenv Dot_dir.env_var ""))

let test_empty_env_var_falls_back () =
  Test_helpers.with_temp_home (fun home ->
      Unix.putenv Dot_dir.env_var "";
      let expected = Filename.concat home ".clawq" in
      let actual = Dot_dir.path () in
      Alcotest.(check string) "empty env falls back" expected actual)

let test_sub_paths () =
  Test_helpers.with_temp_home (fun home ->
      let base = Filename.concat home ".clawq" in
      Alcotest.(check string)
        "config_path"
        (Filename.concat base "config.json")
        (Dot_dir.config_path ());
      Alcotest.(check string)
        "db_path"
        (Filename.concat base "memory.db")
        (Dot_dir.db_path ());
      Alcotest.(check string)
        "sub"
        (Filename.concat base "foo")
        (Dot_dir.sub "foo"))

let test_ensure_creates_dir () =
  Test_helpers.with_temp_home (fun home ->
      let expected = Filename.concat home ".clawq" in
      assert (not (Sys.file_exists expected));
      let result = Dot_dir.ensure () in
      Alcotest.(check string) "ensure returns path" expected result;
      Alcotest.(check bool) "dir exists" true (Sys.file_exists expected))

let test_env_var_name () =
  Alcotest.(check string) "env var name" "CLAWQ_HOME" Dot_dir.env_var

let suite =
  [
    Alcotest.test_case "default uses HOME" `Quick test_default_path_uses_home;
    Alcotest.test_case "CLAWQ_HOME overrides" `Quick test_env_var_overrides_home;
    Alcotest.test_case "empty CLAWQ_HOME falls back" `Quick
      test_empty_env_var_falls_back;
    Alcotest.test_case "sub paths" `Quick test_sub_paths;
    Alcotest.test_case "ensure creates dir" `Quick test_ensure_creates_dir;
    Alcotest.test_case "env var name" `Quick test_env_var_name;
  ]
