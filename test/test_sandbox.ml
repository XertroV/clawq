(* Tests for Sandbox module *)

(* --- backend type tests --- *)

let test_none_backend () =
  let sb = { Sandbox.backend = Sandbox.None; workspace = "/tmp" } in
  Alcotest.(check string)
    "none wraps identity" "ls"
    (Sandbox.wrap_command sb "ls")

let test_firejail_wrap () =
  let sb = { Sandbox.backend = Sandbox.Firejail; workspace = "/workspace" } in
  let wrapped = Sandbox.wrap_command sb "echo hello" in
  let contains s sub =
    try
      ignore (Str.search_forward (Str.regexp_string sub) s 0);
      true
    with Not_found -> false
  in
  Alcotest.(check bool) "contains firejail" true (contains wrapped "firejail");
  Alcotest.(check bool)
    "contains workspace" true
    (contains wrapped "/workspace");
  Alcotest.(check bool) "contains command" true (contains wrapped "echo hello")

let test_bubblewrap_wrap () =
  let sb = { Sandbox.backend = Sandbox.Bubblewrap; workspace = "/workspace" } in
  let wrapped = Sandbox.wrap_command sb "echo hello" in
  let contains s sub =
    try
      ignore (Str.search_forward (Str.regexp_string sub) s 0);
      true
    with Not_found -> false
  in
  Alcotest.(check bool) "contains bwrap" true (contains wrapped "bwrap");
  Alcotest.(check bool)
    "contains workspace" true
    (contains wrapped "/workspace");
  Alcotest.(check bool) "contains command" true (contains wrapped "echo hello")

(* --- is_available tests --- *)

let test_none_always_available () =
  Alcotest.(check bool)
    "None always available" true
    (Sandbox.is_available Sandbox.None)

(* --- detect tests --- *)

let test_detect_returns_backend () =
  let b = Sandbox.detect () in
  (* Should return one of Firejail, Bubblewrap, or None *)
  let is_valid =
    match b with Sandbox.Firejail | Sandbox.Bubblewrap | Sandbox.None -> true
  in
  Alcotest.(check bool) "detect returns valid backend" true is_valid

(* --- create tests --- *)

let test_create_workspace () =
  let sb = Sandbox.create ~workspace:"/test/workspace" () in
  Alcotest.(check string) "workspace" "/test/workspace" sb.workspace

let test_create_sets_backend () =
  let sb = Sandbox.create ~workspace:"/tmp" () in
  let is_valid =
    match sb.backend with
    | Sandbox.Firejail | Sandbox.Bubblewrap | Sandbox.None -> true
  in
  Alcotest.(check bool) "backend set" true is_valid

(* --- bind_if_exists tests --- *)

let test_bind_if_exists_existing () =
  let result = Sandbox.bind_if_exists "/tmp" in
  let contains s sub =
    try
      ignore (Str.search_forward (Str.regexp_string sub) s 0);
      true
    with Not_found -> false
  in
  Alcotest.(check bool)
    "contains /tmp" true
    (contains result "/tmp" || result = "")

let test_bind_if_exists_nonexistent () =
  let result = Sandbox.bind_if_exists "/nonexistent_path_abc_xyz_123" in
  Alcotest.(check string) "empty for nonexistent" "" result

(* --- wrap_command edge cases --- *)

let test_wrap_empty_command () =
  let sb = { Sandbox.backend = Sandbox.None; workspace = "/tmp" } in
  Alcotest.(check string) "empty command" "" (Sandbox.wrap_command sb "")

let test_wrap_firejail_net_none () =
  let sb = { Sandbox.backend = Sandbox.Firejail; workspace = "/tmp" } in
  let wrapped = Sandbox.wrap_command sb "test" in
  let contains s sub =
    try
      ignore (Str.search_forward (Str.regexp_string sub) s 0);
      true
    with Not_found -> false
  in
  Alcotest.(check bool) "net=none" true (contains wrapped "--net=none")

let test_wrap_firejail_quiet () =
  let sb = { Sandbox.backend = Sandbox.Firejail; workspace = "/tmp" } in
  let wrapped = Sandbox.wrap_command sb "test" in
  let contains s sub =
    try
      ignore (Str.search_forward (Str.regexp_string sub) s 0);
      true
    with Not_found -> false
  in
  Alcotest.(check bool) "quiet" true (contains wrapped "--quiet")

let test_wrap_bubblewrap_ro_bind () =
  let sb = { Sandbox.backend = Sandbox.Bubblewrap; workspace = "/tmp" } in
  let wrapped = Sandbox.wrap_command sb "test" in
  let contains s sub =
    try
      ignore (Str.search_forward (Str.regexp_string sub) s 0);
      true
    with Not_found -> false
  in
  Alcotest.(check bool)
    "ro-bind /usr" true
    (contains wrapped "--ro-bind /usr /usr")

let test_wrap_bubblewrap_unshare () =
  let sb = { Sandbox.backend = Sandbox.Bubblewrap; workspace = "/tmp" } in
  let wrapped = Sandbox.wrap_command sb "test" in
  let contains s sub =
    try
      ignore (Str.search_forward (Str.regexp_string sub) s 0);
      true
    with Not_found -> false
  in
  Alcotest.(check bool) "unshare-all" true (contains wrapped "--unshare-all")

let test_wrap_bubblewrap_die_with_parent () =
  let sb = { Sandbox.backend = Sandbox.Bubblewrap; workspace = "/tmp" } in
  let wrapped = Sandbox.wrap_command sb "test" in
  let contains s sub =
    try
      ignore (Str.search_forward (Str.regexp_string sub) s 0);
      true
    with Not_found -> false
  in
  Alcotest.(check bool)
    "die-with-parent" true
    (contains wrapped "--die-with-parent")

let suite =
  [
    Alcotest.test_case "none backend identity" `Quick test_none_backend;
    Alcotest.test_case "firejail wrap" `Quick test_firejail_wrap;
    Alcotest.test_case "bubblewrap wrap" `Quick test_bubblewrap_wrap;
    Alcotest.test_case "none always available" `Quick test_none_always_available;
    Alcotest.test_case "detect returns backend" `Quick
      test_detect_returns_backend;
    Alcotest.test_case "create workspace" `Quick test_create_workspace;
    Alcotest.test_case "create sets backend" `Quick test_create_sets_backend;
    Alcotest.test_case "bind_if_exists existing" `Quick
      test_bind_if_exists_existing;
    Alcotest.test_case "bind_if_exists nonexistent" `Quick
      test_bind_if_exists_nonexistent;
    Alcotest.test_case "wrap empty command" `Quick test_wrap_empty_command;
    Alcotest.test_case "firejail net=none" `Quick test_wrap_firejail_net_none;
    Alcotest.test_case "firejail quiet" `Quick test_wrap_firejail_quiet;
    Alcotest.test_case "bubblewrap ro-bind" `Quick test_wrap_bubblewrap_ro_bind;
    Alcotest.test_case "bubblewrap unshare" `Quick test_wrap_bubblewrap_unshare;
    Alcotest.test_case "bubblewrap die-with-parent" `Quick
      test_wrap_bubblewrap_die_with_parent;
  ]
