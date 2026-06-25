let no_args_skill_name args =
  let open Yojson.Safe.Util in
  let name = try args |> member "name" |> to_string with _ -> "" in
  let arguments =
    try
      let a = args |> member "arguments" in
      if a = `Null then "" else to_string a
    with _ -> ""
  in
  if name <> "" && arguments = "" then Some name else None

let already_loaded_response name =
  Printf.sprintf
    "Skill \"%s\" already loaded in current context; no new instructions \
     injected."
    name

let use_skill_loaded_noop ?reserved_no_arg_skills ~history (tool : Tool.t) args
    =
  if tool.name <> "use_skill" then None
  else
    match no_args_skill_name args with
    | None -> None
    | Some name when Skill_dedup.skill_loaded_in_history history name ->
        Some (already_loaded_response name)
    | Some name -> (
        match reserved_no_arg_skills with
        | None -> None
        | Some reserved ->
            let key = String.lowercase_ascii name in
            if Hashtbl.mem reserved key then Some (already_loaded_response name)
            else begin
              Hashtbl.replace reserved key ();
              None
            end)
