open Cmdliner

let unescape_newlines s =
  let len = String.length s in
  let buf = Buffer.create len in
  let i = ref 0 in
  while !i < len do
    if !i + 1 < len && s.[!i] = '\\' && s.[!i + 1] = 'n' then begin
      Buffer.add_char buf '\n';
      i := !i + 2
    end else begin
      Buffer.add_char buf s.[!i];
      i := !i + 1
    end
  done;
  Buffer.contents buf

let run cmd args =
  let all = cmd :: args in
  print_string (unescape_newlines (Command_bridge.handle all));
  `Ok ()

let cmd_t =
  let cmd =
    let doc = "Subcommand to run (for example: onboard, agent, status, phase2)." in
    Arg.(required & pos 0 (some string) None & info [] ~docv:"COMMAND" ~doc)
  in
  let args =
    let doc = "Additional command arguments." in
    Arg.(value & pos_right 0 string [] & info [] ~docv:"ARGS" ~doc)
  in
  Term.(ret (const run $ cmd $ args))

let info =
  Cmd.info "clawq"
    ~version:"0.1.0-dev"
    ~doc:"Coq port scaffold of nullclaw (runtime skeleton)"
    ~exits:Cmd.Exit.defaults

let () = exit (Cmd.eval (Cmd.v info cmd_t))
