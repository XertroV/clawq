type held_item = {
  id : int;
  feature_name : string;
  description : string;
  plan_json : string;
  layer : int;
  requestor_id : string option;
  channel : string option;
  session_key : string option;
  status : string;
  created_at : string;
  reviewed_by : string option;
  reviewed_at : string option;
  review_notes : string option;
}

let init_db db =
  let exec_exn sql =
    match Sqlite3.exec db sql with
    | Sqlite3.Rc.OK -> ()
    | rc ->
        failwith
          (Printf.sprintf "SQLite error (%s): %s" (Sqlite3.Rc.to_string rc) sql)
  in
  exec_exn
    "CREATE TABLE IF NOT EXISTS held_items (\n\
    \     id INTEGER PRIMARY KEY AUTOINCREMENT,\n\
    \     feature_name TEXT NOT NULL,\n\
    \     description TEXT NOT NULL,\n\
    \     plan_json TEXT NOT NULL,\n\
    \     layer INTEGER NOT NULL DEFAULT 6,\n\
    \     requestor_id TEXT,\n\
    \     channel TEXT,\n\
    \     session_key TEXT,\n\
    \     status TEXT NOT NULL DEFAULT 'pending',\n\
    \     created_at TEXT NOT NULL DEFAULT (datetime('now')),\n\
    \     reviewed_by TEXT,\n\
    \     reviewed_at TEXT,\n\
    \     review_notes TEXT\n\
    \   )";
  exec_exn
    "CREATE INDEX IF NOT EXISTS idx_held_items_status ON held_items (status)"

let text_or_null = function
  | Some s -> Sqlite3.Data.TEXT s
  | None -> Sqlite3.Data.NULL

let text_of_data = function Sqlite3.Data.TEXT s -> Some s | _ -> None
let int_of_data = function Sqlite3.Data.INT n -> Int64.to_int n | _ -> 0

let row_of_stmt stmt =
  {
    id = int_of_data (Sqlite3.column stmt 0);
    feature_name =
      (match text_of_data (Sqlite3.column stmt 1) with
      | Some s -> s
      | None -> "");
    description =
      (match text_of_data (Sqlite3.column stmt 2) with
      | Some s -> s
      | None -> "");
    plan_json =
      (match text_of_data (Sqlite3.column stmt 3) with
      | Some s -> s
      | None -> "");
    layer = int_of_data (Sqlite3.column stmt 4);
    requestor_id = text_of_data (Sqlite3.column stmt 5);
    channel = text_of_data (Sqlite3.column stmt 6);
    session_key = text_of_data (Sqlite3.column stmt 7);
    status =
      (match text_of_data (Sqlite3.column stmt 8) with
      | Some s -> s
      | None -> "pending");
    created_at =
      (match text_of_data (Sqlite3.column stmt 9) with
      | Some s -> s
      | None -> "");
    reviewed_by = text_of_data (Sqlite3.column stmt 10);
    reviewed_at = text_of_data (Sqlite3.column stmt 11);
    review_notes = text_of_data (Sqlite3.column stmt 12);
  }

let save ~db ~feature_name ~description ~plan_json ~layer ?requestor_id ?channel
    ?session_key () =
  let sql =
    "INSERT INTO held_items (feature_name, description, plan_json, layer, \
     requestor_id, channel, session_key) VALUES (?, ?, ?, ?, ?, ?, ?)"
  in
  let stmt = Sqlite3.prepare db sql in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize stmt))
    (fun () ->
      ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT feature_name));
      ignore (Sqlite3.bind stmt 2 (Sqlite3.Data.TEXT description));
      ignore (Sqlite3.bind stmt 3 (Sqlite3.Data.TEXT plan_json));
      ignore (Sqlite3.bind stmt 4 (Sqlite3.Data.INT (Int64.of_int layer)));
      ignore (Sqlite3.bind stmt 5 (text_or_null requestor_id));
      ignore (Sqlite3.bind stmt 6 (text_or_null channel));
      ignore (Sqlite3.bind stmt 7 (text_or_null session_key));
      match Sqlite3.step stmt with
      | Sqlite3.Rc.DONE -> Int64.to_int (Sqlite3.last_insert_rowid db)
      | rc ->
          failwith
            (Printf.sprintf "held_items save error: %s"
               (Sqlite3.Rc.to_string rc)))

let list_items ~db ?(status = "pending") () =
  let sql, bind_status =
    if status = "all" then
      ( "SELECT id, feature_name, description, plan_json, layer, requestor_id, \
         channel, session_key, status, created_at, reviewed_by, reviewed_at, \
         review_notes FROM held_items ORDER BY id DESC",
        false )
    else
      ( "SELECT id, feature_name, description, plan_json, layer, requestor_id, \
         channel, session_key, status, created_at, reviewed_by, reviewed_at, \
         review_notes FROM held_items WHERE status = ? ORDER BY id DESC",
        true )
  in
  let stmt = Sqlite3.prepare db sql in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize stmt))
    (fun () ->
      if bind_status then
        ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT status));
      let rows = ref [] in
      while Sqlite3.step stmt = Sqlite3.Rc.ROW do
        rows := row_of_stmt stmt :: !rows
      done;
      List.rev !rows)

let get ~db ~id =
  let sql =
    "SELECT id, feature_name, description, plan_json, layer, requestor_id, \
     channel, session_key, status, created_at, reviewed_by, reviewed_at, \
     review_notes FROM held_items WHERE id = ?"
  in
  let stmt = Sqlite3.prepare db sql in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize stmt))
    (fun () ->
      ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.INT (Int64.of_int id)));
      match Sqlite3.step stmt with
      | Sqlite3.Rc.ROW -> Some (row_of_stmt stmt)
      | _ -> None)

let review ~db ~id ~action ?reviewed_by ?notes () =
  let sql =
    "UPDATE held_items SET status = ?, reviewed_by = ?, reviewed_at = \
     datetime('now'), review_notes = ? WHERE id = ? AND status = 'pending'"
  in
  let stmt = Sqlite3.prepare db sql in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize stmt))
    (fun () ->
      ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT action));
      ignore (Sqlite3.bind stmt 2 (text_or_null reviewed_by));
      ignore (Sqlite3.bind stmt 3 (text_or_null notes));
      ignore (Sqlite3.bind stmt 4 (Sqlite3.Data.INT (Int64.of_int id)));
      match Sqlite3.step stmt with
      | Sqlite3.Rc.DONE -> Sqlite3.changes db > 0
      | rc ->
          failwith
            (Printf.sprintf "held_items review error: %s"
               (Sqlite3.Rc.to_string rc)))

let delete ~db ~id =
  let sql = "DELETE FROM held_items WHERE id = ?" in
  let stmt = Sqlite3.prepare db sql in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize stmt))
    (fun () ->
      ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.INT (Int64.of_int id)));
      match Sqlite3.step stmt with
      | Sqlite3.Rc.DONE -> Sqlite3.changes db > 0
      | rc ->
          failwith
            (Printf.sprintf "held_items delete error: %s"
               (Sqlite3.Rc.to_string rc)))
