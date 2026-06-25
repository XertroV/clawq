let skill_header_prefix = "[Skill: "

type skill_header_kind = Instructions | Args | Placeholder

let strip_suffix s suffix =
  let slen = String.length s in
  let suffix_len = String.length suffix in
  if slen >= suffix_len && String.sub s (slen - suffix_len) suffix_len = suffix
  then Some (String.sub s 0 (slen - suffix_len))
  else None

let parse_skill_header inj =
  let plen = String.length skill_header_prefix in
  if String.length inj > plen && String.sub inj 0 plen = skill_header_prefix
  then
    match String.index_opt inj ']' with
    | Some i -> (
        let header = String.sub inj plen (i - plen) in
        match strip_suffix header " (args)" with
        | Some name -> Some (name, Args)
        | None -> (
            match strip_suffix header " (autoloaded after compaction)" with
            | Some name -> Some (name, Instructions)
            | None -> (
                match strip_suffix header " (already loaded)" with
                | Some name -> Some (name, Placeholder)
                | None -> Some (header, Instructions))))
    | None -> None
  else None

let extract_skill_name_from_injection inj =
  match parse_skill_header inj with
  | Some (name, Instructions) -> Some name
  | Some (_, (Args | Placeholder)) | None -> None

let loaded_skill_name_from_injection inj =
  match parse_skill_header inj with
  | Some (name, (Instructions | Args)) -> Some name
  | Some (_, Placeholder) | None -> None

let injection_has_args inj =
  match parse_skill_header inj with Some (_, Args) -> true | _ -> false

let skill_loaded_in_history history name =
  let target = String.lowercase_ascii name in
  List.exists
    (fun (msg : Provider.message) ->
      msg.role = "system"
      &&
      match extract_skill_name_from_injection msg.content with
      | Some loaded_name -> String.lowercase_ascii loaded_name = target
      | None -> false)
    history

let loaded_skill_names_in_history history =
  let seen = Hashtbl.create 8 in
  List.iter
    (fun (msg : Provider.message) ->
      if msg.role = "system" then
        match extract_skill_name_from_injection msg.content with
        | Some name -> Hashtbl.replace seen name ()
        | None -> ())
    history;
  Hashtbl.fold (fun name () acc -> name :: acc) seen []

let dedup_skill_injections ~history injections =
  let existing_skills = Hashtbl.create 8 in
  List.iter
    (fun (msg : Provider.message) ->
      if msg.role = "system" then
        match extract_skill_name_from_injection msg.content with
        | Some name -> Hashtbl.replace existing_skills name ()
        | None -> ())
    history;
  List.filter
    (fun inj ->
      injection_has_args inj
      ||
      match extract_skill_name_from_injection inj with
      | Some name -> not (Hashtbl.mem existing_skills name)
      | None -> true)
    injections
