let skill_header_prefix = "[Skill: "

let extract_skill_name_from_injection inj =
  let plen = String.length skill_header_prefix in
  if String.length inj > plen && String.sub inj 0 plen = skill_header_prefix
  then
    match String.index_opt inj ']' with
    | Some i -> Some (String.sub inj plen (i - plen))
    | None -> None
  else None

let injection_has_args inj =
  let args_marker = " (args)" in
  let mlen = String.length args_marker in
  match String.index_opt inj ']' with
  | Some i when i >= mlen -> String.sub inj (i - mlen) mlen = args_marker
  | _ -> false

let dedup_skill_injections ~history injections =
  let existing_skills = Hashtbl.create 8 in
  List.iter
    (fun (msg : Provider.message) ->
      if msg.role = "system" then
        match extract_skill_name_from_injection msg.content with
        | Some name -> Hashtbl.replace existing_skills name ()
        | None -> ())
    history;
  List.map
    (fun inj ->
      if injection_has_args inj then inj
      else
        match extract_skill_name_from_injection inj with
        | Some name when Hashtbl.mem existing_skills name ->
            Printf.sprintf
              "[Skill: %s (already loaded)] Follow the previously loaded \
               instructions for skill \"%s\"."
              name name
        | _ -> inj)
    injections
