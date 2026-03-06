let test_reset_clears_active_session_and_history () =
  let db = Memory.init ~db_path:":memory:" () in
  let config = Runtime_config.default in
  let mgr = Session.create ~config ~db () in
  let agent = Agent.create ~config () in
  Hashtbl.replace mgr.sessions "s1" (agent, Lwt_mutex.create (), ref None);
  Memory.store_message ~db ~session_key:"s1"
    (Provider.make_message ~role:"user" ~content:"hello");
  Lwt_main.run (Session.reset mgr ~key:"s1");
  Alcotest.(check bool)
    "session entry removed" false
    (Hashtbl.mem mgr.sessions "s1");
  Alcotest.(check int)
    "history cleared" 0
    (List.length (Memory.load_history ~db ~session_key:"s1"))

let test_reset_waits_for_session_lock () =
  let db = Memory.init ~db_path:":memory:" () in
  let config = Runtime_config.default in
  let mgr = Session.create ~config ~db () in
  let mutex = Lwt_mutex.create () in
  let agent = Agent.create ~config () in
  Hashtbl.replace mgr.sessions "s1" (agent, mutex, ref None);
  Memory.store_message ~db ~session_key:"s1"
    (Provider.make_message ~role:"user" ~content:"hello");
  Lwt_main.run
    (let open Lwt.Syntax in
     let* () = Lwt_mutex.lock mutex in
     let reset_p = Session.reset mgr ~key:"s1" in
     let* () = Lwt.pause () in
     Alcotest.(check bool)
       "session still present while locked" true
       (Hashtbl.mem mgr.sessions "s1");
     Lwt_mutex.unlock mutex;
     reset_p);
  Alcotest.(check bool)
    "session removed after unlock" false
    (Hashtbl.mem mgr.sessions "s1");
  Alcotest.(check int)
    "history cleared after unlock" 0
    (List.length (Memory.load_history ~db ~session_key:"s1"))

let suite =
  [
    Alcotest.test_case "reset clears active session and history" `Quick
      test_reset_clears_active_session_and_history;
    Alcotest.test_case "reset waits for session lock" `Quick
      test_reset_waits_for_session_lock;
  ]
