include Background_task_db

type wait_result =
  | Finished of task
  | Timeout of task
  | Interrupted of task
  | Not_found

let max_wait_seconds = 110.0

let rec wait_until_terminal ?(timeout_seconds = 110.0) ?(poll_seconds = 1.0)
    ?interrupt_check ~db ~id () =
  let open Lwt.Syntax in
  match get_task ~db ~id with
  | None -> Lwt.return Not_found
  | Some task when is_terminal_status task.status -> Lwt.return (Finished task)
  | Some task when timeout_seconds <= 0.0 -> Lwt.return (Timeout task)
  | Some _ ->
      let sleep_for = Float.min poll_seconds timeout_seconds in
      let* () = Lwt_unix.sleep sleep_for in
      (* B473: only abandon the wait for real interrupt reasons (restart,
         user-issued cancel). A pending queued inbound message is delivered
         inline at the end of the agent turn and should not collapse a
         background_task_wait into a 1-second no-op. *)
      let interrupted =
        match interrupt_check with
        | Some check -> (
            match check () with
            | None -> false
            | Some reason when reason = Agent.queued_message_interrupt_token ->
                false
            | Some _ -> true)
        | None -> false
      in
      if interrupted then
        match get_task ~db ~id with
        | None -> Lwt.return Not_found
        | Some task -> Lwt.return (Interrupted task)
      else
        wait_until_terminal
          ~timeout_seconds:(timeout_seconds -. sleep_for)
          ~poll_seconds ?interrupt_check ~db ~id ()

let read_last_lines path ~lines =
  if lines <= 0 then Ok []
  else
    try
      let ic = open_in path in
      Fun.protect
        ~finally:(fun () -> close_in_noerr ic)
        (fun () ->
          let rec loop acc count =
            match input_line ic with
            | line ->
                let acc =
                  if count >= lines then List.tl acc @ [ line ]
                  else acc @ [ line ]
                in
                loop acc (min lines (count + 1))
            | exception End_of_file -> Ok acc
          in
          loop [] 0)
    with Sys_error msg -> Error msg

let permission_rejection_markers =
  [ "permission requested:"; "auto-rejecting"; "The user rejected permission" ]

let looks_like_permission_rejection output =
  List.exists
    (fun needle -> String_util.contains output needle)
    permission_rejection_markers

let classify_task_result ~exit_code ~output =
  if exit_code <> 0 then Failed
  else if looks_like_permission_rejection output then Failed
  else Succeeded

let result_preview_of_output ~exit_code ~output =
  if output = "" then Printf.sprintf "Process exited with code %d" exit_code
  else Printf.sprintf "exit %d: %s" exit_code output

let read_command_first_line command =
  try
    let ic = Unix.open_process_in command in
    let line = try Some (input_line ic) with End_of_file -> None in
    let exit_code =
      match Unix.close_process_in ic with
      | Unix.WEXITED code -> code
      | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> 128
    in
    (exit_code, line)
  with _ -> (128, None)

let worktree_harvest_issue (task : task) =
  match (task.use_worktree, task.worktree_path) with
  | false, _ | _, None -> None
  | true, Some worktree_path when not (path_is_git_repo worktree_path) ->
      Some
        "Task worktree is no longer a git repository; changes cannot be \
         harvested"
  | true, Some worktree_path -> (
      let command =
        Printf.sprintf
          "git -C %s status --porcelain --untracked-files=normal 2>&1"
          (Filename.quote worktree_path)
      in
      let exit_code, first_line = read_command_first_line command in
      if exit_code <> 0 then
        Some
          (Printf.sprintf "Unable to inspect task worktree for harvesting%s"
             (match first_line with
             | Some line when String.trim line <> "" -> ": " ^ String.trim line
             | _ -> ""))
      else
        match first_line with
        | Some line when String.trim line <> "" ->
            Some
              (Printf.sprintf
                 "Task left uncommitted worktree changes that cannot be \
                  harvested: %s"
                 (String.trim line))
        | _ -> None)

let completion_outcome ~db ~id ~exit_code ~output =
  let default_preview = result_preview_of_output ~exit_code ~output in
  match get_task ~db ~id with
  | Some { status = Cancelled; _ } -> (Cancelled, default_preview)
  | Some task -> (
      match classify_task_result ~exit_code ~output with
      | Failed -> (Failed, default_preview)
      | Succeeded -> (
          match worktree_harvest_issue task with
          | Some issue -> (DirtyWorktree, issue)
          | None -> (Succeeded, default_preview))
      | DirtyWorktree | Cancelled | Queued | Running -> (Failed, default_preview)
      )
  | None -> (classify_task_result ~exit_code ~output, default_preview)

let read_lines_window path ~offset ~limit =
  if limit <= 0 then Ok ([], 0)
  else
    try
      let ic = open_in path in
      Fun.protect
        ~finally:(fun () -> close_in_noerr ic)
        (fun () ->
          let rec loop line_num acc collected =
            match input_line ic with
            | line ->
                if line_num >= offset && collected < limit then
                  loop (line_num + 1) ((line_num, line) :: acc) (collected + 1)
                else if collected >= limit then
                  let rec count n =
                    match input_line ic with
                    | _ -> count (n + 1)
                    | exception End_of_file -> n
                  in
                  let total = count line_num in
                  Ok (List.rev acc, total)
                else loop (line_num + 1) acc collected
            | exception End_of_file -> Ok (List.rev acc, line_num - 1)
          in
          loop 1 [] 0)
    with Sys_error msg -> Error msg

let count_lines path =
  try
    let ic = open_in path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr ic)
      (fun () ->
        let count = ref 0 in
        (try
           while true do
             ignore (input_line ic);
             incr count
           done
         with End_of_file -> ());
        !count)
  with Sys_error _ -> 0

let background_task_logs_max_chars = 3000
let background_task_logs_max_line_chars = 1200
let background_task_logs_max_lines = 200

let truncate_background_task_log_line line =
  if String.length line <= background_task_logs_max_line_chars then (line, false)
  else
    ( String.sub line 0 background_task_logs_max_line_chars
      ^ Printf.sprintf " ...(truncated %d chars)"
          (String.length line - background_task_logs_max_line_chars),
      true )

let trim_rendered_lines ~max_chars lines =
  let budget = max 0 max_chars in
  let rec take acc used remaining =
    match remaining with
    | [] -> (List.rev acc, false)
    | line :: rest ->
        let line_len = String.length line in
        let sep_len = if acc = [] then 0 else 1 in
        if used + sep_len + line_len <= budget then
          take (line :: acc) (used + sep_len + line_len) rest
        else (List.rev acc, true)
  in
  take [] 0 lines

let render_background_task_log_lines indexed_lines =
  let truncated_any_line = ref false in
  let numbered_lines =
    indexed_lines
    |> List.map (fun (n, line) ->
        let line, truncated = truncate_background_task_log_line line in
        if truncated then truncated_any_line := true;
        Printf.sprintf "%d: %s" n line)
  in
  let rendered_lines, truncated_by_budget =
    trim_rendered_lines ~max_chars:background_task_logs_max_chars numbered_lines
  in
  (rendered_lines, truncated_by_budget, !truncated_any_line)

let log_excerpt ?db ?connector ?(offset = 0) ?(lines = 20) task =
  match (task.acp, db) with
  | true, Some db when Acp_history.has_history ~db ~task_id:task.id ->
      let connector =
        match connector with Some c -> c | None -> Format_adapter.Plain
      in
      Ok
        (Acp_history.format_for_display_rich ~db ~task_id:task.id ~connector
           ~max_lines:lines ())
  | _ -> (
      match task.log_path with
      | None -> Error (Printf.sprintf "Task %d has no log file yet" task.id)
      | Some path when not (Sys.file_exists path) ->
          Error (Printf.sprintf "Log file does not exist yet: %s" path)
      | Some path ->
          if offset > 0 then
            read_lines_window path ~offset ~limit:lines
            |> Result.map (fun (indexed_lines, total) ->
                let header =
                  Printf.sprintf "Log excerpt for task %d (%s)\npath: %s"
                    task.id
                    (string_of_status task.status)
                    path
                in
                if indexed_lines = [] then
                  header
                  ^ Printf.sprintf
                      "\n\n(No lines in requested range. Log has %d lines.)"
                      total
                else
                  let rendered_lines, truncated, truncated_any_line =
                    render_background_task_log_lines indexed_lines
                  in
                  let rendered = String.concat "\n" rendered_lines in
                  let last_line = fst (List.hd (List.rev indexed_lines)) in
                  let suffix =
                    if truncated then
                      let next_offset = offset + List.length rendered_lines in
                      Printf.sprintf
                        "\n\n\
                         (Output truncated by size budget. Showing lines %d-%d \
                         of %d. Use offset=%d to continue.)"
                        offset
                        (offset + List.length rendered_lines - 1)
                        total next_offset
                    else if last_line < total then
                      Printf.sprintf
                        "\n\n\
                         (Showing lines %d-%d of %d. Use offset=%d to \
                         continue.)"
                        offset last_line total (last_line + 1)
                    else
                      Printf.sprintf "\n\n(End of log - total %d lines)" total
                  in
                  let trunc_suffix =
                    if truncated_any_line then
                      Printf.sprintf
                        "\n\n(Note: long log lines are truncated to %d chars.)"
                        background_task_logs_max_line_chars
                    else ""
                  in
                  header ^ "\n\n" ^ rendered ^ suffix ^ trunc_suffix)
          else
            read_last_lines path ~lines
            |> Result.map (fun chunks ->
                let header =
                  Printf.sprintf "Log excerpt for task %d (%s)\npath: %s"
                    task.id
                    (string_of_status task.status)
                    path
                in
                if chunks = [] then header ^ "\n\n(log file is empty)"
                else
                  let total = count_lines path in
                  let n_returned = List.length chunks in
                  let start_num = max 1 (total - n_returned + 1) in
                  let indexed_lines =
                    List.mapi (fun i line -> (start_num + i, line)) chunks
                  in
                  let rendered_lines, truncated, truncated_any_line =
                    render_background_task_log_lines indexed_lines
                  in
                  let rendered = String.concat "\n" rendered_lines in
                  let shown = List.length rendered_lines in
                  let shown_start = start_num in
                  let shown_end = start_num + shown - 1 in
                  let footer =
                    if truncated then
                      Printf.sprintf
                        "\n\n\
                         (Output truncated by size budget. Showing lines %d-%d \
                         of %d. Use offset=%d to continue.)"
                        shown_start shown_end total (shown_end + 1)
                    else
                      Printf.sprintf
                        "\n\n(Showing last %d lines, lines %d-%d of %d.)" shown
                        shown_start shown_end total
                  in
                  let trunc_suffix =
                    if truncated_any_line then
                      Printf.sprintf
                        "\n\n(Note: long log lines are truncated to %d chars.)"
                        background_task_logs_max_line_chars
                    else ""
                  in
                  header ^ "\n\n" ^ rendered ^ footer ^ trunc_suffix))

let read_lines_range path ~offset ~lines =
  if lines <= 0 then Ok ([], 0)
  else
    try
      let ic = open_in path in
      Fun.protect
        ~finally:(fun () -> close_in_noerr ic)
        (fun () ->
          let line_num = ref 0 in
          (* Skip to offset *)
          (try
             while !line_num < offset do
               ignore (input_line ic);
               incr line_num
             done
           with End_of_file -> ());
          (* Read up to lines *)
          let acc = ref [] in
          let count = ref 0 in
          (try
             while !count < lines do
               let line = input_line ic in
               acc := line :: !acc;
               incr count;
               incr line_num
             done
           with End_of_file -> ());
          Ok (List.rev !acc, !line_num))
    with Sys_error msg -> Error msg

let log_range ~offset ~lines task =
  match task.log_path with
  | None -> Error (Printf.sprintf "Task %d has no log file yet" task.id)
  | Some path when not (Sys.file_exists path) ->
      Error (Printf.sprintf "Log file does not exist yet: %s" path)
  | Some path ->
      let total_lines = count_lines path in
      read_lines_range path ~offset ~lines
      |> Result.map (fun (chunks, next_line) ->
          let has_more = next_line < total_lines in
          let header =
            Printf.sprintf
              "Log for task %d (%s)\n\
               path: %s\n\
               total_lines: %d\n\
               offset: %d\n\
               showing: %d"
              task.id
              (string_of_status task.status)
              path total_lines offset (List.length chunks)
          in
          let continuation =
            if has_more then
              Printf.sprintf "\nhas_more: true\nnext_offset: %d" next_line
            else "\nhas_more: false"
          in
          if chunks = [] then
            header ^ continuation ^ "\n\n(no lines in requested range)"
          else header ^ continuation ^ "\n\n" ^ String.concat "\n" chunks)

let file_size path =
  try
    let ic = open_in path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr ic)
      (fun () -> in_channel_length ic)
  with Sys_error _ -> 0

let read_from_offset path ~offset =
  try
    let ic = open_in path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr ic)
      (fun () ->
        let file_len = in_channel_length ic in
        if file_len > offset then begin
          seek_in ic offset;
          let len = file_len - offset in
          let buf = Bytes.create len in
          let actually_read = input ic buf 0 len in
          Some (Bytes.sub_string buf 0 actually_read, offset + actually_read)
        end
        else None)
  with Sys_error _ -> None

let log_follow ?(poll_seconds = 0.5) ~db ~id ~initial_lines
    ?(emit =
      fun s ->
        print_string s;
        flush stdout) () =
  let open Lwt.Syntax in
  let rec wait_for_task () =
    match get_task ~db ~id with
    | None ->
        Lwt.return_error
          (Printf.sprintf "No background task found with id %d" id)
    | Some task
      when task.log_path = None && not (is_terminal_status task.status) ->
        let* () = Lwt_unix.sleep poll_seconds in
        wait_for_task ()
    | Some task -> Lwt.return_ok task
  in
  let* task_result = wait_for_task () in
  match task_result with
  | Error msg -> Lwt.return_error msg
  | Ok task -> (
      match task.log_path with
      | None ->
          Lwt.return_error
            (Printf.sprintf "Task %d finished with no log file" task.id)
      | Some path ->
          let header =
            Printf.sprintf "Following log for task %d (%s)\npath: %s\n\n"
              task.id
              (string_of_status task.status)
              path
          in
          emit header;
          (* Print initial tail lines, then track offset from end of file *)
          let offset = ref 0 in
          if Sys.file_exists path then begin
            (match read_last_lines path ~lines:initial_lines with
            | Ok chunks when chunks <> [] ->
                emit (String.concat "\n" chunks ^ "\n")
            | _ -> ());
            offset := file_size path
          end;
          let rec follow () =
            (* Read any new content *)
            (match read_from_offset path ~offset:!offset with
            | Some (s, new_offset) when s <> "" ->
                emit s;
                offset := new_offset
            | _ -> ());
            (* Check task status *)
            match get_task ~db ~id with
            | None -> Lwt.return_ok ()
            | Some task when is_terminal_status task.status ->
                (* One final read *)
                (match read_from_offset path ~offset:!offset with
                | Some (s, _) when s <> "" -> emit s
                | _ -> ());
                emit
                  (Printf.sprintf "\n--- Task %d %s ---\n" task.id
                     (string_of_status task.status));
                Lwt.return_ok ()
            | Some _ ->
                let* () = Lwt_unix.sleep poll_seconds in
                follow ()
          in
          follow ())

let finalize_completed_task ~db ~id ~exit_code ~output =
  match get_task ~db ~id with
  | Some { status = Queued; _ } -> Queued
  | _ ->
      let final_status, result_preview =
        completion_outcome ~db ~id ~exit_code ~output
      in
      finish ~db ~id ~status:final_status ~result_preview;
      final_status
