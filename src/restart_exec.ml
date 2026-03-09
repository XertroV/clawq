let reexec_path_env = "CLAWQ_REEXEC_PATH"

let executable () =
  match Sys.getenv_opt reexec_path_env with
  | Some path when String.trim path <> "" -> String.trim path
  | _ -> Sys.executable_name
