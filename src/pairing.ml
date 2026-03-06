type pair_result =
  | Paired of string (* the bearer token *)
  | WrongCode
  | Locked of float (* locked until unix timestamp *)
  | AlreadyPaired

type status = {
  code : string;
  attempts : int;
  locked : bool;
  paired_count : int;
}

type t = {
  mutable code : string;
  mutable attempts : int;
  mutable locked_until : float option;
  mutable paired_tokens : string list; (* sha256 hashes *)
  max_attempts : int;
  lockout_seconds : float;
}

let ensure_rng_initialized = lazy (Mirage_crypto_rng_unix.use_default ())

let generate_code () =
  Lazy.force ensure_rng_initialized;
  let raw = Mirage_crypto_rng.generate 4 in
  let n =
    (Char.code raw.[0] lsl 16)
    lor (Char.code raw.[1] lsl 8)
    lor Char.code raw.[2]
  in
  Printf.sprintf "%06d" (n mod 1_000_000)

let hash_token token = Digestif.SHA256.(digest_string token |> to_hex)

let create ~max_attempts ~lockout_seconds () =
  {
    code = generate_code ();
    attempts = 0;
    locked_until = None;
    paired_tokens = [];
    max_attempts;
    lockout_seconds;
  }

let try_pair t ~code =
  let now = Unix.gettimeofday () in
  match t.locked_until with
  | Some until when now < until -> Locked until
  | _ ->
      t.locked_until <- None;
      if Eqaf.equal code t.code then begin
        Lazy.force ensure_rng_initialized;
        let raw_token = Mirage_crypto_rng.generate 32 in
        let token = Base64.encode_string raw_token in
        let hashed = hash_token token in
        t.paired_tokens <- hashed :: t.paired_tokens;
        t.attempts <- 0;
        Paired token
      end
      else begin
        t.attempts <- t.attempts + 1;
        if t.attempts >= t.max_attempts then begin
          t.locked_until <- Some (now +. t.lockout_seconds);
          Locked (now +. t.lockout_seconds)
        end
        else WrongCode
      end

let regenerate_code t =
  t.code <- generate_code ();
  t.attempts <- 0;
  t.locked_until <- None

let is_valid_token t ~token =
  let hashed = hash_token token in
  List.exists (fun h -> Eqaf.equal h hashed) t.paired_tokens

let status t =
  let now = Unix.gettimeofday () in
  let locked =
    match t.locked_until with Some until -> now < until | None -> false
  in
  {
    code = t.code;
    attempts = t.attempts;
    locked;
    paired_count = List.length t.paired_tokens;
  }
