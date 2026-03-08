let collect_tool_call_ids msgs =
  List.fold_left
    (fun acc (m : Provider.message) ->
      if m.role = "assistant" && m.tool_calls <> [] then
        List.fold_left
          (fun acc (tc : Provider.tool_call) ->
            if List.mem tc.id acc then acc else tc.id :: acc)
          acc m.tool_calls
      else acc)
    [] msgs

let collect_tool_result_ids msgs =
  List.fold_left
    (fun acc (m : Provider.message) ->
      match m.tool_call_id with
      | Some id when m.role = "tool" ->
          if List.mem id acc then acc else id :: acc
      | _ -> acc)
    [] msgs

let ensure_tool_group_integrity msgs =
  let call_ids = collect_tool_call_ids msgs in
  let result_ids = collect_tool_result_ids msgs in
  msgs
  |> List.filter (fun (m : Provider.message) ->
      if m.role = "tool" then
        match m.tool_call_id with
        | Some id -> List.mem id call_ids
        | None -> true
      else true)
  |> List.map (fun (m : Provider.message) ->
      if m.role = "assistant" && m.tool_calls <> [] then
        let kept =
          List.filter
            (fun (tc : Provider.tool_call) -> List.mem tc.id result_ids)
            m.tool_calls
        in
        { m with tool_calls = kept }
      else m)

let adjust_split_for_tool_groups to_compact to_keep =
  let rec move_orphans compact keep =
    match keep with
    | (msg : Provider.message) :: rest when msg.role = "tool" ->
        move_orphans (compact @ [ msg ]) rest
    | _ -> (compact, keep)
  in
  move_orphans to_compact to_keep

let expand_keep_for_tool_groups to_compact to_keep =
  let rec loop compact keep =
    match keep with
    | (msg : Provider.message) :: _ when msg.role = "tool" -> (
        match List.rev compact with
        | prev :: rest_rev -> loop (List.rev rest_rev) (prev :: keep)
        | [] -> keep)
    | _ -> keep
  in
  loop to_compact to_keep
