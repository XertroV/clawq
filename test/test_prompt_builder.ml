let contains hay needle =
  let hlen = String.length hay in
  let nlen = String.length needle in
  let rec loop i =
    if i + nlen > hlen then false
    else if String.sub hay i nlen = needle then true
    else loop (i + 1)
  in
  nlen = 0 || loop 0

let with_temp_workspace f =
  let base = Filename.get_temp_dir_name () in
  let dir =
    Filename.concat base
      (Printf.sprintf "clawq_prompt_%d_%d" (Unix.getpid ()) (Random.bits ()))
  in
  (try Unix.rmdir dir with _ -> ());
  Unix.mkdir dir 0o755;
  Fun.protect
    (fun () -> f dir)
    ~finally:(fun () -> try Unix.rmdir dir with _ -> ())

let write_file path content =
  let oc = open_out path in
  output_string oc content;
  close_out oc

let test_dynamic_prompt_disabled_uses_base_prompt () =
  with_temp_workspace (fun workspace ->
      let prompt_cfg =
        { Runtime_config.default.prompt with dynamic_enabled = false }
      in
      let cfg =
        { Runtime_config.default with workspace; prompt = prompt_cfg }
      in
      let prompt = Prompt_builder.build ~config:cfg ~tool_registry:None () in
      Alcotest.(check string)
        "dynamic disabled returns base prompt" Prompt_builder.base_prompt prompt)

let test_default_prompt_enables_dynamic_workspace_context () =
  Alcotest.(check bool)
    "default dynamic prompt enabled" true
    Runtime_config.default.prompt.dynamic_enabled

let test_dynamic_prompt_includes_workspace_files () =
  with_temp_workspace (fun workspace ->
      write_file (Filename.concat workspace "EGO.md") "EGO SENTINEL";
      write_file (Filename.concat workspace "AGENTS.md") "AGENTS SENTINEL";
      let prompt_cfg =
        {
          Runtime_config.default.prompt with
          dynamic_enabled = true;
          include_tools_section = false;
          include_safety_section = false;
          include_runtime_section = false;
          include_datetime_section = false;
          workspace_files = [ "EGO.md"; "AGENTS.md" ];
        }
      in
      let cfg =
        { Runtime_config.default with workspace; prompt = prompt_cfg }
      in
      let prompt = Prompt_builder.build ~config:cfg ~tool_registry:None () in
      Alcotest.(check bool)
        "has workspace section" true
        (contains prompt "## Workspace Context");
      Alcotest.(check bool)
        "includes EGO contents" true
        (contains prompt "EGO SENTINEL");
      Alcotest.(check bool)
        "includes AGENTS contents" true
        (contains prompt "AGENTS SENTINEL"))

let test_dynamic_prompt_includes_self_reference () =
  with_temp_workspace (fun workspace ->
      let cfg = { Runtime_config.default with workspace } in
      let prompt = Prompt_builder.build ~config:cfg ~tool_registry:None () in
      Alcotest.(check bool)
        "has self-reference section" true
        (contains prompt "## Self-Reference");
      Alcotest.(check bool)
        "has llms-full.txt URL" true
        (contains prompt "https://clawq.org/llms-full.txt"))

let test_runtime_context_includes_git_details () =
  with_temp_workspace (fun workspace ->
      let git_dir = Filename.concat workspace ".git" in
      let refs_heads = Filename.concat git_dir "refs/heads" in
      Unix.mkdir git_dir 0o755;
      Unix.mkdir (Filename.concat git_dir "refs") 0o755;
      Unix.mkdir refs_heads 0o755;
      write_file (Filename.concat git_dir "HEAD") "ref: refs/heads/main\n";
      write_file (Filename.concat refs_heads "main") "0123456789abcdef\n";
      let prompt_cfg =
        {
          Runtime_config.default.prompt with
          dynamic_enabled = true;
          include_runtime_section = true;
          include_datetime_section = false;
        }
      in
      let cfg =
        { Runtime_config.default with workspace; prompt = prompt_cfg }
      in
      let cwd_before = Sys.getcwd () in
      Fun.protect
        (fun () ->
          Sys.chdir workspace;
          let runtime =
            Prompt_builder.build_runtime_context ~config:cfg ()
            |> Option.value ~default:""
          in
          Alcotest.(check bool) "includes os" true (contains runtime "- OS: ");
          Alcotest.(check bool)
            "includes repo root" true
            (contains runtime ("- Git repo root: " ^ workspace));
          Alcotest.(check bool)
            "includes git branch" true
            (contains runtime "- Git branch: main"))
        ~finally:(fun () -> Sys.chdir cwd_before))

let suite =
  [
    Alcotest.test_case "dynamic prompt disabled uses base prompt" `Quick
      test_dynamic_prompt_disabled_uses_base_prompt;
    Alcotest.test_case "default prompt enables dynamic workspace context" `Quick
      test_default_prompt_enables_dynamic_workspace_context;
    Alcotest.test_case "dynamic prompt includes workspace files" `Quick
      test_dynamic_prompt_includes_workspace_files;
    Alcotest.test_case "dynamic prompt includes self-reference" `Quick
      test_dynamic_prompt_includes_self_reference;
    Alcotest.test_case "runtime context includes git details" `Quick
      test_runtime_context_includes_git_details;
  ]
