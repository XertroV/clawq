let env_var = "CLAWQ_HOME"

let path () =
  match Sys.getenv_opt env_var with
  | Some dir when dir <> "" -> dir
  | _ ->
      let home = try Sys.getenv "HOME" with Not_found -> "/tmp" in
      Filename.concat home ".clawq"

let ensure () =
  let p = path () in
  (try if not (Sys.file_exists p) then Sys.mkdir p 0o755 with _ -> ());
  p

let sub name = Filename.concat (path ()) name
let config_path () = sub "config.json"
let db_path () = sub "memory.db"
