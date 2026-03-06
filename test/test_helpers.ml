(* Test helpers for clawq test suite *)

(** Create an in-memory SQLite database, call f with it, close after *)
let with_memory_db f =
  let db = Sqlite3.db_open ":memory:" in
  let result = f db in
  ignore (Sqlite3.db_close db);
  result

(** Create a temp directory, call f with path, cleanup after *)
let with_temp_dir f =
  let dir = Filename.temp_file "clawq_test_" "" in
  Unix.unlink dir;
  Unix.mkdir dir 0o700;
  let result =
    try f dir
    with exn ->
      (try
         let files = Sys.readdir dir in
         Array.iter
           (fun file ->
             try Unix.unlink (Filename.concat dir file) with _ -> ())
           files;
         Unix.rmdir dir
       with _ -> ());
      raise exn
  in
  (try
     let files = Sys.readdir dir in
     Array.iter
       (fun file -> try Unix.unlink (Filename.concat dir file) with _ -> ())
       files;
     Unix.rmdir dir
   with _ -> ());
  result

(** Assert result is Ok, return value *)
let assert_ok = function
  | Ok v -> v
  | Error e -> Alcotest.failf "Expected Ok, got Error: %s" e

(** Assert result is Error *)
let assert_error = function
  | Ok _ -> Alcotest.fail "Expected Error, got Ok"
  | Error _ -> ()
