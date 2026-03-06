type backend = Firejail | Bubblewrap | None
type t = { backend : backend; workspace : string }

let is_available b =
  let cmd =
    match b with
    | Firejail -> "which firejail 2>/dev/null"
    | Bubblewrap -> "which bwrap 2>/dev/null"
    | None -> ""
  in
  if cmd = "" then true else Sys.command cmd = 0

let detect () =
  if is_available Firejail then Firejail
  else if is_available Bubblewrap then Bubblewrap
  else None

let create ~workspace () =
  let backend = detect () in
  { backend; workspace }

let bind_if_exists path =
  if Sys.file_exists path then
    " --bind " ^ Filename.quote path ^ " " ^ Filename.quote path
  else ""

let wrap_command t cmd =
  match t.backend with
  | None -> cmd
  | Firejail ->
      Printf.sprintf
        "firejail --private=%s --net=none --quiet --noprofile -- %s"
        (Filename.quote t.workspace)
        cmd
  | Bubblewrap ->
      let extra_binds =
        bind_if_exists "/lib" ^ bind_if_exists "/lib64" ^ bind_if_exists "/bin"
      in
      Printf.sprintf
        "bwrap --ro-bind /usr /usr --unshare-all --bind %s %s%s \
         --die-with-parent -- %s"
        (Filename.quote t.workspace)
        (Filename.quote t.workspace)
        extra_binds cmd
