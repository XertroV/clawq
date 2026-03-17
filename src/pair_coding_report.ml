(* Markdown report generation for pair coding sessions. *)

let format_duration_secs secs =
  if secs < 60.0 then Printf.sprintf "%.0fs" secs
  else if secs < 3600.0 then
    Printf.sprintf "%dm %ds" (int_of_float secs / 60) (int_of_float secs mod 60)
  else
    Printf.sprintf "%dh %dm"
      (int_of_float secs / 3600)
      (int_of_float secs mod 3600 / 60)

let generate ~db ~id =
  match Pair_coding_state.load_session ~db ~id with
  | None -> Printf.sprintf "Error: pair session '%s' not found." id
  | Some s ->
      let notes = Pair_coding_state.load_notes ~db ~session_id:id in
      let buf = Buffer.create 1024 in
      let add fmt = Printf.ksprintf (Buffer.add_string buf) fmt in
      add "# Pair Coding Report: %s\n\n" id;
      add "## Task\n%s\n\n" s.config.task_description;
      add "## Session Info\n";
      add "- Phase: %s\n" (Pair_coding_types.phase_to_string s.phase);
      add "- Review rounds: %d / %d\n" s.review_round s.config.max_review_rounds;
      add "- Started: %s\n" s.created_at;
      (match s.finished_at with
      | Some f -> add "- Finished: %s\n" f
      | None -> add "- Finished: (still active)\n");
      (* Models *)
      add "- Coder model: %s\n"
        (match s.config.coder_model with Some m -> m | None -> "(default)");
      add "- Observer model: %s\n"
        (match s.config.observer_model with Some m -> m | None -> "(default)");
      add "- Coordinator model: %s\n"
        (match s.config.coordinator_model with
        | Some m -> m
        | None -> "(default)");
      add "\n";
      (* Approval *)
      add "## Review Outcome\n";
      add "- Coder: %s%s\n"
        (if s.coder_approved then "APPROVED" else "pending")
        (if s.coder_comment <> "" then " — " ^ s.coder_comment else "");
      add "- Observer: %s%s\n"
        (if s.observer_approved then "APPROVED" else "pending")
        (if s.observer_comment <> "" then " — " ^ s.observer_comment else "");
      add "\n";
      (* Notes *)
      if notes = [] then add "## Notes\nNo notes recorded.\n\n"
      else begin
        let critical =
          List.filter
            (fun (n : Pair_coding_types.note) -> n.severity = Critical)
            notes
        in
        let high =
          List.filter
            (fun (n : Pair_coding_types.note) -> n.severity = High)
            notes
        in
        let medium =
          List.filter
            (fun (n : Pair_coding_types.note) -> n.severity = Medium)
            notes
        in
        let low =
          List.filter
            (fun (n : Pair_coding_types.note) -> n.severity = Low)
            notes
        in
        let format_notes label (ns : Pair_coding_types.note list) =
          if ns <> [] then begin
            add "### %s (%d)\n" label (List.length ns);
            List.iter
              (fun (n : Pair_coding_types.note) ->
                let resolved_mark = if n.resolved then " [RESOLVED]" else "" in
                let location =
                  match (n.file, n.line) with
                  | Some f, Some l -> Printf.sprintf " (%s:%d)" f l
                  | Some f, None -> Printf.sprintf " (%s)" f
                  | _ -> ""
                in
                let cat =
                  match n.category with
                  | Some c ->
                      Printf.sprintf " [%s]"
                        (Pair_coding_types.category_to_string c)
                  | None -> ""
                in
                add "- #%d%s%s%s: %s\n" n.id cat location resolved_mark
                  n.description)
              ns;
            add "\n"
          end
        in
        add "## Notes (%d total)\n" (List.length notes);
        format_notes "Critical" critical;
        format_notes "High" high;
        format_notes "Medium" medium;
        format_notes "Low" low
      end;
      (* Stats *)
      let resolved_count =
        List.length
          (List.filter (fun (n : Pair_coding_types.note) -> n.resolved) notes)
      in
      add "## Stats\n";
      add "- Total notes: %d\n" (List.length notes);
      add "- Resolved: %d\n" resolved_count;
      add "- Unresolved: %d\n" (List.length notes - resolved_count);
      Buffer.contents buf
