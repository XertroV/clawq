let record ~db ~session_key ?message_id ~provider ~model ~prompt_tokens
    ~completion_tokens ?cost_usd () =
  let sql =
    "INSERT INTO request_stats (session_key, message_id, provider, model, \
     prompt_tokens, completion_tokens, cost_usd) VALUES (?, ?, ?, ?, ?, ?, ?)"
  in
  try
    let stmt = Sqlite3.prepare db sql in
    Fun.protect
      ~finally:(fun () -> ignore (Sqlite3.finalize stmt))
      (fun () ->
        ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT session_key));
        ignore
          (Sqlite3.bind stmt 2
             (match message_id with
             | Some id -> Sqlite3.Data.INT (Int64.of_int id)
             | None -> Sqlite3.Data.NULL));
        ignore (Sqlite3.bind stmt 3 (Sqlite3.Data.TEXT provider));
        ignore (Sqlite3.bind stmt 4 (Sqlite3.Data.TEXT model));
        ignore
          (Sqlite3.bind stmt 5 (Sqlite3.Data.INT (Int64.of_int prompt_tokens)));
        ignore
          (Sqlite3.bind stmt 6
             (Sqlite3.Data.INT (Int64.of_int completion_tokens)));
        ignore
          (Sqlite3.bind stmt 7
             (match cost_usd with
             | Some c -> Sqlite3.Data.FLOAT c
             | None -> Sqlite3.Data.NULL));
        match Sqlite3.step stmt with
        | Sqlite3.Rc.DONE ->
            Logs.debug (fun m ->
                m "request_stats: recorded %s/%s pt=%d ct=%d" provider model
                  prompt_tokens completion_tokens)
        | rc ->
            Logs.warn (fun m ->
                m "request_stats insert failed: %s" (Sqlite3.Rc.to_string rc)))
  with exn ->
    Logs.warn (fun m ->
        m "request_stats record error: %s" (Printexc.to_string exn))
