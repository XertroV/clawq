(* Tests for Pairing module *)

let test_create_fresh_state () =
  let p = Pairing.create ~max_attempts:3 ~lockout_seconds:60.0 () in
  let s = Pairing.status p in
  Alcotest.(check int) "no attempts initially" 0 s.attempts;
  Alcotest.(check bool) "not locked initially" false s.locked;
  Alcotest.(check int) "no paired tokens initially" 0 s.paired_count

let test_generate_code_length () =
  let p = Pairing.create ~max_attempts:3 ~lockout_seconds:60.0 () in
  let s = Pairing.status p in
  Alcotest.(check int) "code is 6 chars" 6 (String.length s.code)

let test_generate_code_is_numeric () =
  let p = Pairing.create ~max_attempts:3 ~lockout_seconds:60.0 () in
  let s = Pairing.status p in
  let all_digits =
    String.to_seq s.code |> Seq.for_all (fun c -> c >= '0' && c <= '9')
  in
  Alcotest.(check bool) "code is all digits" true all_digits

let test_generate_code_uniqueness () =
  (* Generate many codes and verify they vary *)
  let codes =
    List.init 20 (fun _ ->
        let p = Pairing.create ~max_attempts:3 ~lockout_seconds:60.0 () in
        (Pairing.status p).code)
  in
  (* At least some should differ (probability of collision extremely low) *)
  let unique = List.sort_uniq String.compare codes in
  Alcotest.(check bool)
    "codes are not all identical" true
    (List.length unique > 1)

let test_hash_token_non_empty () =
  let h = Pairing.hash_token "some-token" in
  Alcotest.(check bool) "hash is non-empty" true (String.length h > 0)

let test_hash_token_consistent () =
  let h1 = Pairing.hash_token "my-token" in
  let h2 = Pairing.hash_token "my-token" in
  Alcotest.(check string) "same token same hash" h1 h2

let test_hash_token_different_for_different_inputs () =
  let h1 = Pairing.hash_token "token-a" in
  let h2 = Pairing.hash_token "token-b" in
  Alcotest.(check bool) "different tokens different hashes" true (h1 <> h2)

let test_hash_token_length () =
  (* SHA256 hex = 64 chars *)
  let h = Pairing.hash_token "hello" in
  Alcotest.(check int) "hash is 64 hex chars" 64 (String.length h)

let test_try_pair_correct_code () =
  let p = Pairing.create ~max_attempts:5 ~lockout_seconds:60.0 () in
  let code = (Pairing.status p).code in
  match Pairing.try_pair p ~code with
  | Pairing.Paired token ->
      Alcotest.(check bool) "token non-empty" true (String.length token > 0)
  | Pairing.WrongCode -> Alcotest.fail "expected Paired"
  | Pairing.Locked _ -> Alcotest.fail "expected Paired, got Locked"
  | Pairing.AlreadyPaired -> Alcotest.fail "expected Paired, got AlreadyPaired"

let test_try_pair_correct_increments_paired_count () =
  let p = Pairing.create ~max_attempts:5 ~lockout_seconds:60.0 () in
  let code = (Pairing.status p).code in
  ignore (Pairing.try_pair p ~code);
  let s = Pairing.status p in
  Alcotest.(check int) "paired count is 1" 1 s.paired_count

let test_try_pair_wrong_code_returns_wrong_code () =
  let p = Pairing.create ~max_attempts:5 ~lockout_seconds:60.0 () in
  match Pairing.try_pair p ~code:"999999" with
  | Pairing.WrongCode -> ()
  | Pairing.Paired _ -> Alcotest.fail "expected WrongCode"
  | Pairing.Locked _ -> Alcotest.fail "expected WrongCode, got Locked"
  | Pairing.AlreadyPaired -> Alcotest.fail "expected WrongCode"

let test_try_pair_wrong_code_increments_attempts () =
  let p = Pairing.create ~max_attempts:5 ~lockout_seconds:60.0 () in
  ignore (Pairing.try_pair p ~code:"000000");
  let s = Pairing.status p in
  Alcotest.(check int) "attempts incremented" 1 s.attempts

let test_try_pair_multiple_wrong_increments () =
  let p = Pairing.create ~max_attempts:5 ~lockout_seconds:60.0 () in
  ignore (Pairing.try_pair p ~code:"000000");
  ignore (Pairing.try_pair p ~code:"000000");
  ignore (Pairing.try_pair p ~code:"000000");
  let s = Pairing.status p in
  Alcotest.(check int) "3 attempts" 3 s.attempts

let test_try_pair_max_attempts_locks () =
  let p = Pairing.create ~max_attempts:3 ~lockout_seconds:60.0 () in
  ignore (Pairing.try_pair p ~code:"000000");
  ignore (Pairing.try_pair p ~code:"000000");
  let result = Pairing.try_pair p ~code:"000000" in
  match result with
  | Pairing.Locked _ -> ()
  | _ -> Alcotest.fail "expected Locked after max attempts"

let test_try_pair_locked_returns_locked () =
  let p = Pairing.create ~max_attempts:2 ~lockout_seconds:60.0 () in
  ignore (Pairing.try_pair p ~code:"000000");
  ignore (Pairing.try_pair p ~code:"000000");
  let s_before = Pairing.status p in
  ignore (Pairing.try_pair p ~code:"000000");
  let s_after = Pairing.status p in
  (* Attempts should not increase while locked *)
  Alcotest.(check int)
    "attempts not incremented when locked" s_before.attempts s_after.attempts

let test_try_pair_locked_status () =
  let p = Pairing.create ~max_attempts:2 ~lockout_seconds:60.0 () in
  ignore (Pairing.try_pair p ~code:"000000");
  ignore (Pairing.try_pair p ~code:"000000");
  let s = Pairing.status p in
  Alcotest.(check bool) "is locked" true s.locked

let test_try_pair_resets_attempts_on_success () =
  let p = Pairing.create ~max_attempts:5 ~lockout_seconds:60.0 () in
  ignore (Pairing.try_pair p ~code:"000000");
  ignore (Pairing.try_pair p ~code:"000000");
  let code = (Pairing.status p).code in
  ignore (Pairing.try_pair p ~code);
  let s = Pairing.status p in
  Alcotest.(check int) "attempts reset after success" 0 s.attempts

let test_regenerate_code_changes_code () =
  let p = Pairing.create ~max_attempts:3 ~lockout_seconds:60.0 () in
  let old_code = (Pairing.status p).code in
  (* Regenerate multiple times to ensure it changes eventually *)
  let found_different = ref false in
  for _ = 1 to 10 do
    Pairing.regenerate_code p;
    let new_code = (Pairing.status p).code in
    if new_code <> old_code then found_different := true
  done;
  Alcotest.(check bool) "code changed after regenerate" true !found_different

let test_regenerate_code_resets_attempts () =
  let p = Pairing.create ~max_attempts:5 ~lockout_seconds:60.0 () in
  ignore (Pairing.try_pair p ~code:"000000");
  ignore (Pairing.try_pair p ~code:"000000");
  Pairing.regenerate_code p;
  let s = Pairing.status p in
  Alcotest.(check int) "attempts reset to 0" 0 s.attempts

let test_regenerate_code_unlocks () =
  let p = Pairing.create ~max_attempts:2 ~lockout_seconds:60.0 () in
  ignore (Pairing.try_pair p ~code:"000000");
  ignore (Pairing.try_pair p ~code:"000000");
  Alcotest.(check bool) "locked before" true (Pairing.status p).locked;
  Pairing.regenerate_code p;
  let s = Pairing.status p in
  Alcotest.(check bool) "unlocked after regenerate" false s.locked

let test_is_valid_token_paired () =
  let p = Pairing.create ~max_attempts:5 ~lockout_seconds:60.0 () in
  let code = (Pairing.status p).code in
  match Pairing.try_pair p ~code with
  | Pairing.Paired token ->
      Alcotest.(check bool)
        "token is valid" true
        (Pairing.is_valid_token p ~token)
  | _ -> Alcotest.fail "expected Paired"

let test_is_valid_token_unknown () =
  let p = Pairing.create ~max_attempts:5 ~lockout_seconds:60.0 () in
  Alcotest.(check bool)
    "unknown token invalid" false
    (Pairing.is_valid_token p ~token:"not-a-real-token")

let test_is_valid_token_empty_string () =
  let p = Pairing.create ~max_attempts:5 ~lockout_seconds:60.0 () in
  Alcotest.(check bool)
    "empty token invalid" false
    (Pairing.is_valid_token p ~token:"")

let test_is_valid_token_multiple_pairings () =
  let p = Pairing.create ~max_attempts:5 ~lockout_seconds:60.0 () in
  let code1 = (Pairing.status p).code in
  let token1 =
    match Pairing.try_pair p ~code:code1 with
    | Pairing.Paired t -> t
    | _ -> Alcotest.fail "expected first Paired"
  in
  Pairing.regenerate_code p;
  let code2 = (Pairing.status p).code in
  let token2 =
    match Pairing.try_pair p ~code:code2 with
    | Pairing.Paired t -> t
    | _ -> Alcotest.fail "expected second Paired"
  in
  Alcotest.(check bool)
    "token1 still valid" true
    (Pairing.is_valid_token p ~token:token1);
  Alcotest.(check bool)
    "token2 valid" true
    (Pairing.is_valid_token p ~token:token2)

let test_status_returns_code_length () =
  let p = Pairing.create ~max_attempts:3 ~lockout_seconds:60.0 () in
  let s = Pairing.status p in
  Alcotest.(check int) "status code length" 6 (String.length s.code)

let test_status_attempt_count () =
  let p = Pairing.create ~max_attempts:5 ~lockout_seconds:60.0 () in
  ignore (Pairing.try_pair p ~code:"111111");
  ignore (Pairing.try_pair p ~code:"111111");
  let s = Pairing.status p in
  Alcotest.(check int) "2 attempts in status" 2 s.attempts

let test_status_paired_count () =
  let p = Pairing.create ~max_attempts:5 ~lockout_seconds:60.0 () in
  let code = (Pairing.status p).code in
  ignore (Pairing.try_pair p ~code);
  Pairing.regenerate_code p;
  let code2 = (Pairing.status p).code in
  ignore (Pairing.try_pair p ~code:code2);
  let s = Pairing.status p in
  Alcotest.(check int) "2 paired tokens" 2 s.paired_count

let test_lockout_with_different_max_attempts () =
  (* max_attempts=1 means first failure locks *)
  let p = Pairing.create ~max_attempts:1 ~lockout_seconds:60.0 () in
  let result = Pairing.try_pair p ~code:"000000" in
  match result with
  | Pairing.Locked _ -> ()
  | _ -> Alcotest.fail "expected Locked with max_attempts=1"

let test_try_pair_very_long_code_rejected () =
  let p = Pairing.create ~max_attempts:5 ~lockout_seconds:60.0 () in
  let long_code = String.make 100 '0' in
  match Pairing.try_pair p ~code:long_code with
  | Pairing.WrongCode -> ()
  | Pairing.Locked _ -> ()
  | Pairing.Paired _ -> Alcotest.fail "very long code should not match"
  | Pairing.AlreadyPaired -> ()

let test_try_pair_empty_code_rejected () =
  let p = Pairing.create ~max_attempts:5 ~lockout_seconds:60.0 () in
  match Pairing.try_pair p ~code:"" with
  | Pairing.WrongCode -> ()
  | Pairing.Locked _ -> ()
  | Pairing.Paired _ -> Alcotest.fail "empty code should not match"
  | Pairing.AlreadyPaired -> ()

let test_lockout_then_correct_code_eventually () =
  (* After lockout expires (simulated by low lockout_seconds), try correct code.
     We can't wait in tests so just verify the structure is correct *)
  let p = Pairing.create ~max_attempts:2 ~lockout_seconds:0.001 () in
  ignore (Pairing.try_pair p ~code:"000000");
  ignore (Pairing.try_pair p ~code:"000000");
  (* Locked for 0.001s *)
  Unix.sleepf 0.01;
  (* Now try correct code - should work after lockout expires *)
  let code = (Pairing.status p).code in
  match Pairing.try_pair p ~code with
  | Pairing.Paired _ -> ()
  | Pairing.WrongCode -> Alcotest.fail "expected Paired after lockout expired"
  | Pairing.Locked _ ->
      Alcotest.fail "expected to be unlocked after lockout_seconds elapsed"
  | Pairing.AlreadyPaired -> ()

let test_try_pair_correct_code_after_wrong () =
  let p = Pairing.create ~max_attempts:5 ~lockout_seconds:60.0 () in
  ignore (Pairing.try_pair p ~code:"000000");
  let code = (Pairing.status p).code in
  match Pairing.try_pair p ~code with
  | Pairing.Paired _ -> ()
  | _ -> Alcotest.fail "correct code after wrong should still work"

let test_paired_count_is_cumulative () =
  let p = Pairing.create ~max_attempts:10 ~lockout_seconds:60.0 () in
  for _ = 1 to 3 do
    let code = (Pairing.status p).code in
    ignore (Pairing.try_pair p ~code);
    Pairing.regenerate_code p
  done;
  let s = Pairing.status p in
  Alcotest.(check int) "3 cumulative pairings" 3 s.paired_count

let test_not_locked_initially_with_high_attempts () =
  let p = Pairing.create ~max_attempts:100 ~lockout_seconds:60.0 () in
  let s = Pairing.status p in
  Alcotest.(check bool) "not locked" false s.locked

let suite =
  [
    Alcotest.test_case "create fresh state" `Quick test_create_fresh_state;
    Alcotest.test_case "generate code length" `Quick test_generate_code_length;
    Alcotest.test_case "generate code is numeric" `Quick
      test_generate_code_is_numeric;
    Alcotest.test_case "generate code uniqueness" `Quick
      test_generate_code_uniqueness;
    Alcotest.test_case "hash token non-empty" `Quick test_hash_token_non_empty;
    Alcotest.test_case "hash token consistent" `Quick test_hash_token_consistent;
    Alcotest.test_case "hash token different inputs" `Quick
      test_hash_token_different_for_different_inputs;
    Alcotest.test_case "hash token length" `Quick test_hash_token_length;
    Alcotest.test_case "try_pair correct code" `Quick test_try_pair_correct_code;
    Alcotest.test_case "try_pair correct increments paired count" `Quick
      test_try_pair_correct_increments_paired_count;
    Alcotest.test_case "try_pair wrong code returns WrongCode" `Quick
      test_try_pair_wrong_code_returns_wrong_code;
    Alcotest.test_case "try_pair wrong code increments attempts" `Quick
      test_try_pair_wrong_code_increments_attempts;
    Alcotest.test_case "try_pair multiple wrong increments" `Quick
      test_try_pair_multiple_wrong_increments;
    Alcotest.test_case "try_pair max attempts locks" `Quick
      test_try_pair_max_attempts_locks;
    Alcotest.test_case "try_pair locked returns Locked" `Quick
      test_try_pair_locked_returns_locked;
    Alcotest.test_case "try_pair locked status" `Quick
      test_try_pair_locked_status;
    Alcotest.test_case "try_pair resets attempts on success" `Quick
      test_try_pair_resets_attempts_on_success;
    Alcotest.test_case "regenerate code changes code" `Quick
      test_regenerate_code_changes_code;
    Alcotest.test_case "regenerate code resets attempts" `Quick
      test_regenerate_code_resets_attempts;
    Alcotest.test_case "regenerate code unlocks" `Quick
      test_regenerate_code_unlocks;
    Alcotest.test_case "is_valid_token paired" `Quick test_is_valid_token_paired;
    Alcotest.test_case "is_valid_token unknown" `Quick
      test_is_valid_token_unknown;
    Alcotest.test_case "is_valid_token empty string" `Quick
      test_is_valid_token_empty_string;
    Alcotest.test_case "is_valid_token multiple pairings" `Quick
      test_is_valid_token_multiple_pairings;
    Alcotest.test_case "status attempt count" `Quick test_status_attempt_count;
    Alcotest.test_case "status paired count" `Quick test_status_paired_count;
    Alcotest.test_case "status returns code length" `Quick
      test_status_returns_code_length;
    Alcotest.test_case "lockout with max_attempts=1" `Quick
      test_lockout_with_different_max_attempts;
    Alcotest.test_case "very long code rejected" `Quick
      test_try_pair_very_long_code_rejected;
    Alcotest.test_case "empty code rejected" `Quick
      test_try_pair_empty_code_rejected;
    Alcotest.test_case "lockout then correct code" `Quick
      test_lockout_then_correct_code_eventually;
    Alcotest.test_case "correct code after wrong" `Quick
      test_try_pair_correct_code_after_wrong;
    Alcotest.test_case "paired count is cumulative" `Quick
      test_paired_count_is_cumulative;
    Alcotest.test_case "not locked initially with high attempts" `Quick
      test_not_locked_initially_with_high_attempts;
  ]
