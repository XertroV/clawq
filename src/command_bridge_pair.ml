(* CLI commands for pair coding sessions. *)

open Command_bridge_helpers

let parse_flags args =
  let rec loop acc = function
    | [] -> acc
    | "--coder-model" :: v :: rest ->
        loop { acc with Pair_coding_state.coder_model = Some v } rest
    | "--observer-model" :: v :: rest ->
        loop { acc with observer_model = Some v } rest
    | "--coordinator-model" :: v :: rest ->
        loop { acc with coordinator_model = Some v } rest
    | "--workspace" :: v :: rest -> loop { acc with workspace = Some v } rest
    | "--worktree" :: rest ->
        loop { acc with worktree_path = Some "(auto)" } rest
    | "--branch" :: v :: rest -> loop { acc with branch_name = Some v } rest
    | "--max-rounds" :: v :: rest -> (
        match int_of_string_opt v with
        | Some n -> loop { acc with max_review_rounds = n } rest
        | None -> loop acc rest)
    | "--interrupt-mode" :: v :: rest -> (
        match Pair_coding_types.interrupt_mode_of_string v with
        | Some m -> loop { acc with interrupt_mode = m } rest
        | None -> loop acc rest)
    | _ :: rest -> loop acc rest
  in
  loop
    {
      task_description = "";
      max_review_rounds = 3;
      interrupt_mode = Pair_coding_types.Asap;
      workspace = None;
      worktree_path = None;
      branch_name = None;
      auto_swap_roles = false;
      coder_model = None;
      observer_model = None;
      coordinator_model = None;
    }
    args

let extract_task args =
  let rec collect acc = function
    | [] -> List.rev acc
    | s :: _ when String.length s > 2 && String.sub s 0 2 = "--" -> List.rev acc
    | s :: rest -> collect (s :: acc) rest
  in
  String.concat " " (collect [] args)

let cmd_pair_start args =
  let task = extract_task args in
  if task = "" then
    "Usage: clawq pair start <task description> [--coder-model M] \
     [--observer-model M] [--coordinator-model M] [--max-rounds N] \
     [--interrupt-mode asap|urgent_only|queued]"
  else
    let config = parse_flags args in
    let config = { config with task_description = task } in
    let db = get_db () in
    let cfg = get_config () in
    let session_mgr =
      Session_core.create ~config:cfg
        ?tool_registry:(build_tool_registry ~db:(Some db) cfg)
        ~db ()
    in
    let result =
      Lwt_main.run (Pair_coding_session.start_session ~db ~session_mgr ~config)
    in
    match result with
    | Ok info ->
        Printf.sprintf
          "Pair coding session started: %s\n\
           Coder key: %s\n\
           Observer key: %s\n\
           Coordinator key: %s\n\
           Task: %s"
          info.id info.coder_key info.observer_key info.coordinator_key task
    | Error msg -> Printf.sprintf "Error: %s" msg

let cmd_pair_status args =
  match args with
  | [] | [ "" ] -> (
      let active = Pair_coding_session.list_active () in
      match active with
      | [] -> "No active pair coding sessions."
      | sessions ->
          let lines =
            List.map
              (fun (s : Pair_coding_session.pair_session_info) ->
                Printf.sprintf "%s: %s (started %.0fs ago)" s.id
                  (String.sub s.config.task_description 0
                     (min 60 (String.length s.config.task_description)))
                  (Unix.gettimeofday () -. s.started_at))
              sessions
          in
          "Active pair sessions:\n" ^ String.concat "\n" lines)
  | [ id ] -> (
      let db = get_db () in
      match Pair_coding_state.load_session ~db ~id with
      | None -> Printf.sprintf "Pair session '%s' not found." id
      | Some s ->
          let notes = Pair_coding_state.load_notes ~db ~session_id:id in
          let unresolved =
            List.filter
              (fun (n : Pair_coding_types.note) -> not n.resolved)
              notes
          in
          Printf.sprintf
            "Session: %s\n\
             Phase: %s\n\
             Active: %b\n\
             Review round: %d / %d\n\
             Task: %s\n\
             Notes: %d total, %d unresolved\n\
             Coder approval: %s\n\
             Observer approval: %s\n\
             Created: %s%s"
            s.id
            (Pair_coding_types.phase_to_string s.phase)
            s.active s.review_round s.config.max_review_rounds
            s.config.task_description (List.length notes)
            (List.length unresolved)
            (if s.coder_approved then "approved" else "pending")
            (if s.observer_approved then "approved" else "pending")
            s.created_at
            (match s.finished_at with
            | Some f -> "\nFinished: " ^ f
            | None -> ""))
  | _ -> "Usage: clawq pair status [id]"

let cmd_pair_list _args =
  let db = get_db () in
  let sessions = Pair_coding_state.list_sessions ~db () in
  if sessions = [] then "No pair coding sessions found."
  else
    let lines =
      List.map
        (fun (s : Pair_coding_state.session_record) ->
          Printf.sprintf "%s  %s  %s  %s" s.id
            (Pair_coding_types.phase_to_string s.phase)
            (if s.active then "active" else "done")
            (let desc = s.config.task_description in
             if String.length desc > 50 then String.sub desc 0 50 ^ "..."
             else desc))
        sessions
    in
    "ID       Phase       Status  Task\n" ^ String.concat "\n" lines

let cmd_pair_stop args =
  match args with
  | [ id ] -> (
      let db = get_db () in
      let cfg = get_config () in
      let session_mgr = Session_core.create ~config:cfg ~db () in
      let result =
        Lwt_main.run (Pair_coding_session.stop_session ~db ~session_mgr ~id)
      in
      match result with
      | Ok (Some report) -> report
      | Ok None -> Printf.sprintf "Session '%s' stopped." id
      | Error msg -> Printf.sprintf "Error: %s" msg)
  | [] -> "Usage: clawq pair stop <id>"
  | _ -> "Usage: clawq pair stop <id>"

let cmd_pair_report args =
  match args with
  | [ id ] ->
      let db = get_db () in
      Pair_coding_report.generate ~db ~id
  | [] -> "Usage: clawq pair report <id>"
  | _ -> "Usage: clawq pair report <id>"

let cmd_pair_notes args =
  match args with
  | [ id ] ->
      let db = get_db () in
      let notes = Pair_coding_state.load_notes ~db ~session_id:id in
      if notes = [] then Printf.sprintf "No notes for session '%s'." id
      else
        let lines =
          List.map
            (fun (n : Pair_coding_types.note) ->
              Printf.sprintf "#%d [%s] %s%s%s" n.id
                (Pair_coding_types.severity_to_string n.severity)
                (if n.resolved then "[RESOLVED] " else "")
                n.description
                (match n.file with
                | Some f ->
                    Printf.sprintf " (%s%s)" f
                      (match n.line with
                      | Some l -> Printf.sprintf ":%d" l
                      | None -> "")
                | None -> ""))
            notes
        in
        String.concat "\n" lines
  | [] -> "Usage: clawq pair notes <id>"
  | _ -> "Usage: clawq pair notes <id>"

let cmd_pair args =
  match args with
  | "start" :: rest -> cmd_pair_start rest
  | "status" :: rest -> cmd_pair_status rest
  | "list" :: rest -> cmd_pair_list rest
  | "stop" :: rest -> cmd_pair_stop rest
  | "report" :: rest -> cmd_pair_report rest
  | "notes" :: rest -> cmd_pair_notes rest
  | [] | [ "" ] ->
      "Usage: clawq pair <subcommand>\n\n\
       Subcommands:\n\
      \  start <task> [flags]  Start a pair coding session\n\
      \  status [id]           Show session status\n\
      \  list                  List all pair sessions\n\
      \  stop <id>             Stop a pair session\n\
      \  report <id>           Generate session report\n\
      \  notes <id>            List observer notes\n\n\
       Flags for 'start':\n\
      \  --coder-model M       Model for coder agent\n\
      \  --observer-model M    Model for observer agent\n\
      \  --coordinator-model M Model for coordinator agent\n\
      \  --max-rounds N        Maximum review rounds (default: 3)\n\
      \  --interrupt-mode M    Interrupt mode: asap|urgent_only|queued"
  | cmd :: _ -> Printf.sprintf "Unknown pair subcommand: %s" cmd
