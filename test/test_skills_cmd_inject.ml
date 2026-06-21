let test_find_injections_single () =
  let result = Skills_cmd_inject.find_injections "before !`echo hi` after" in
  Alcotest.(check int) "one match" 1 (List.length result);
  let full, cmd = List.hd result in
  Alcotest.(check string) "full match" "!`echo hi`" full;
  Alcotest.(check string) "command" "echo hi" cmd

let test_find_injections_multiple () =
  let result = Skills_cmd_inject.find_injections "a !`cmd1` b !`cmd2` c" in
  Alcotest.(check int) "two matches" 2 (List.length result);
  let _, cmd1 = List.nth result 0 in
  let _, cmd2 = List.nth result 1 in
  Alcotest.(check string) "first cmd" "cmd1" cmd1;
  Alcotest.(check string) "second cmd" "cmd2" cmd2

let test_find_injections_none () =
  let result = Skills_cmd_inject.find_injections "no injections here" in
  Alcotest.(check int) "no matches" 0 (List.length result)

let test_find_injections_plain_backtick () =
  let result = Skills_cmd_inject.find_injections "some `code` here" in
  Alcotest.(check int) "no match for plain backtick" 0 (List.length result)

let test_execute_injection_echo () =
  let result =
    Lwt_main.run (Skills_cmd_inject.execute_injection "echo hello")
  in
  Alcotest.(check string) "echo output" "hello" result

let test_execute_injection_timeout () =
  let result =
    Lwt_main.run
      (Skills_cmd_inject.execute_injection ~timeout_secs:0.2 "sleep 10")
  in
  Alcotest.(check bool)
    "timeout error" true
    (try
       ignore (Str.search_forward (Str.regexp_string "timed out") result 0);
       true
     with Not_found -> false)

let test_execute_injection_skill_dir_path () =
  let dir = Filename.temp_dir "skill_dir_test" "" in
  let script_path = Filename.concat dir "my-helper" in
  let oc = open_out script_path in
  output_string oc "#!/bin/sh\necho skill-dir-works\n";
  close_out oc;
  Unix.chmod script_path 0o755;
  let result =
    Lwt_main.run
      (Skills_cmd_inject.execute_injection ~skill_dir:dir "my-helper")
  in
  Alcotest.(check string) "script found via PATH" "skill-dir-works" result;
  Sys.remove script_path;
  try Sys.rmdir dir with _ -> ()

let test_execute_injection_workspace_blocked () =
  let result =
    Lwt_main.run
      (Skills_cmd_inject.execute_injection ~workspace_only:true "echo a | cat")
  in
  Alcotest.(check bool)
    "blocked" true
    (try
       ignore
         (Str.search_forward (Str.regexp_string "cmd-inject error") result 0);
       true
     with Not_found -> false)

let test_execute_injection_workspace_path_includes_user_bins () =
  Test_helpers.with_temp_home (fun home ->
      let pnpm_home = Filename.concat home ".local/share/pnpm" in
      Unix.mkdir (Filename.concat home ".local") 0o755;
      Unix.mkdir (Filename.concat home ".local/share") 0o755;
      Unix.mkdir pnpm_home 0o755;
      let helper = Filename.concat pnpm_home "skill-helper" in
      let oc = open_out helper in
      output_string oc "#!/bin/sh\necho pnpm-home-helper\n";
      close_out oc;
      Unix.chmod helper 0o755;
      let result =
        Lwt_main.run
          (Skills_cmd_inject.execute_injection ~workspace_only:true
             ~allowed_commands:[ "skill-helper" ] "skill-helper")
      in
      Alcotest.(check string) "helper found via PATH" "pnpm-home-helper" result)

let test_expand_injections_full () =
  let body = "start !`echo one` middle !`echo two` end" in
  let result = Lwt_main.run (Skills_cmd_inject.expand_injections body) in
  Alcotest.(check string) "expanded" "start one middle two end" result

let test_expand_injections_passthrough () =
  let body = "no injections here" in
  let result = Lwt_main.run (Skills_cmd_inject.expand_injections body) in
  Alcotest.(check string) "unchanged" "no injections here" result

let suite =
  [
    Alcotest.test_case "find_injections single" `Quick
      test_find_injections_single;
    Alcotest.test_case "find_injections multiple" `Quick
      test_find_injections_multiple;
    Alcotest.test_case "find_injections none" `Quick test_find_injections_none;
    Alcotest.test_case "find_injections plain backtick" `Quick
      test_find_injections_plain_backtick;
    Alcotest.test_case "execute injection echo" `Quick
      test_execute_injection_echo;
    Alcotest.test_case "execute injection timeout" `Quick
      test_execute_injection_timeout;
    Alcotest.test_case "execute injection skill dir path" `Quick
      test_execute_injection_skill_dir_path;
    Alcotest.test_case "execute injection workspace blocked" `Quick
      test_execute_injection_workspace_blocked;
    Alcotest.test_case "execute injection user bin PATH" `Quick
      test_execute_injection_workspace_path_includes_user_bins;
    Alcotest.test_case "expand injections full" `Quick
      test_expand_injections_full;
    Alcotest.test_case "expand injections passthrough" `Quick
      test_expand_injections_passthrough;
  ]
