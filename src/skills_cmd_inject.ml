let find_injections body =
  let len = String.length body in
  let results = ref [] in
  let i = ref 0 in
  while !i < len - 2 do
    if body.[!i] = '!' && body.[!i + 1] = '`' then begin
      let start = !i in
      let j = ref (!i + 2) in
      while !j < len && body.[!j] <> '`' do
        incr j
      done;
      if !j < len then begin
        let full = String.sub body start (!j - start + 1) in
        let cmd = String.sub body (start + 2) (!j - start - 2) in
        results := (full, cmd) :: !results;
        i := !j + 1
      end
      else i := !j
    end
    else incr i
  done;
  List.rev !results

let execute_injection ?(workspace_only = false)
    ?(allowed_commands = Tools_builtin.default_shell_allowlist)
    ?(timeout_secs = 10.0) ?skill_dir cmd =
  let open Lwt.Syntax in
  if workspace_only && Tools_builtin.has_unsafe_shell_syntax cmd then
    Lwt.return
      (Printf.sprintf "[cmd-inject error: unsafe shell syntax in command: %s]"
         cmd)
  else if
    workspace_only
    && not (Tools_builtin.is_command_allowed ~allowed_commands cmd)
  then
    Lwt.return
      (Printf.sprintf "[cmd-inject error: command '%s' not in allowlist]"
         (Tools_builtin.extract_command cmd))
  else
    let base_env =
      if workspace_only then Runtime_config.workspace_only_env ()
      else Runtime_config.augment_env_path (Unix.environment ())
    in
    let env =
      match skill_dir with
      | Some dir ->
          Array.map
            (fun entry ->
              let prefix = "PATH=" in
              let plen = String.length prefix in
              if String.length entry >= plen && String.sub entry 0 plen = prefix
              then
                let old_path =
                  String.sub entry plen (String.length entry - plen)
                in
                "PATH=" ^ dir ^ ":" ^ old_path
              else entry)
            base_env
      | None -> base_env
    in
    let cwd = if workspace_only then Some (Sys.getcwd ()) else None in
    let proc = Process_group.start ?cwd ~env (Process_group.Shell cmd) in
    let runner_result, runner_wakener = Lwt.wait () in
    let forced_result = ref None in
    let finish_runner result =
      if Lwt.is_sleeping runner_result then
        Lwt.wakeup_later runner_wakener result
    in
    Lwt.async (fun () ->
        Lwt.catch
          (fun () ->
            Lwt.finalize
              (fun () ->
                let* stdout, stderr =
                  Lwt.both
                    (Lwt_io.read proc.Process_group.stdout)
                    (Lwt_io.read proc.Process_group.stderr)
                in
                let* status = Process_group.wait proc.pid in
                let exit_code =
                  match status with
                  | Unix.WEXITED n -> n
                  | Unix.WSIGNALED n -> 128 + n
                  | Unix.WSTOPPED n -> 128 + n
                in
                if exit_code = 0 then finish_runner (Ok (String.trim stdout))
                else
                  finish_runner
                    (Error
                       (Printf.sprintf "[cmd-inject error: exit %d, stderr: %s]"
                          exit_code (String.trim stderr)));
                Lwt.return_unit)
              (fun () -> Process_group.close proc))
          (fun exn ->
            finish_runner
              (Error
                 (Printf.sprintf "[cmd-inject error: %s]"
                    (Printexc.to_string exn)));
            Lwt.return_unit));
    let* result =
      Lwt.pick
        [
          (let* result = runner_result in
           match !forced_result with
           | Some output -> Lwt.return (Error output)
           | None -> Lwt.return result);
          (let* () = Lwt_unix.sleep timeout_secs in
           let output =
             Printf.sprintf "[cmd-inject error: timed out after %.0f seconds]"
               timeout_secs
           in
           forced_result := Some output;
           let* () = Process_group.terminate proc.pid in
           let* _ = runner_result in
           Lwt.return (Error output));
        ]
    in
    match result with Ok s -> Lwt.return s | Error s -> Lwt.return s

let expand_injections ?workspace_only ?allowed_commands ?timeout_secs ?skill_dir
    body =
  let injections = find_injections body in
  if injections = [] then Lwt.return body
  else
    let open Lwt.Syntax in
    let current = ref body in
    let* () =
      Lwt_list.iter_s
        (fun (full_match, cmd) ->
          let* replacement =
            execute_injection ?workspace_only ?allowed_commands ?timeout_secs
              ?skill_dir cmd
          in
          let buf = Buffer.create (String.length !current) in
          let flen = String.length full_match in
          let blen = String.length !current in
          let i = ref 0 in
          let replaced = ref false in
          while !i < blen do
            if
              (not !replaced)
              && !i + flen <= blen
              && String.sub !current !i flen = full_match
            then begin
              Buffer.add_string buf replacement;
              i := !i + flen;
              replaced := true
            end
            else begin
              Buffer.add_char buf !current.[!i];
              incr i
            end
          done;
          current := Buffer.contents buf;
          Lwt.return_unit)
        injections
    in
    Lwt.return !current
