module Lru_dedup = struct
  type t = { tbl : (string, unit) Hashtbl.t; queue : string Queue.t; max : int }

  let create max =
    { tbl = Hashtbl.create (max * 2); queue = Queue.create (); max }

  let mem t id = Hashtbl.mem t.tbl id

  let evict_if_full t =
    if Queue.length t.queue >= t.max then begin
      let old = Queue.pop t.queue in
      Hashtbl.remove t.tbl old
    end

  let mark t id =
    if not (Hashtbl.mem t.tbl id) then begin
      evict_if_full t;
      Hashtbl.replace t.tbl id ();
      Queue.push id t.queue
    end

  let check_and_mark t id =
    if Hashtbl.mem t.tbl id then true
    else begin
      evict_if_full t;
      Queue.push id t.queue;
      Hashtbl.add t.tbl id ();
      false
    end
end

(* Back up from a byte offset to avoid splitting a multi-byte UTF-8 char.
   UTF-8 continuation bytes have the form 10xxxxxx (0x80..0xBF). *)
let utf8_safe_offset text pos =
  let rec back i =
    if i <= 0 then i
    else
      let b = Char.code text.[i] in
      if b land 0xC0 = 0x80 then back (i - 1) else i
  in
  back pos

let chunk_text ?(prefer_newline_break = true) ?(utf8_safe = false) ~max_len text
    =
  let len = String.length text in
  if max_len <= 0 || len <= max_len then [ text ]
  else
    let rec go off acc =
      if off >= len then List.rev acc
      else
        let remaining = len - off in
        if remaining <= max_len then
          go len (String.sub text off remaining :: acc)
        else
          let limit = off + max_len in
          let break_at =
            if prefer_newline_break then
              let rec find i =
                if i <= off then limit
                else if text.[i] = '\n' then i + 1
                else find (i - 1)
              in
              find (limit - 1)
            else limit
          in
          let break_at =
            if utf8_safe then
              let ba = utf8_safe_offset text break_at in
              if ba <= off then off + max_len else ba
            else break_at
          in
          let chunk_len = break_at - off in
          go break_at (String.sub text off chunk_len :: acc)
    in
    go 0 []

let is_allowed ~allowlist id =
  match allowlist with [ "*" ] -> true | ids -> List.mem id ids

module Backoff = struct
  type t = { mutable value : float; initial : float; max : float }

  let create ?(initial = 1.0) ?(max_val = 60.0) () =
    { value = initial; initial; max = max_val }

  let reset t = t.value <- t.initial
  let current t = t.value
  let increase t = t.value <- Float.min (t.value *. 2.0) t.max

  let sleep_and_increase t =
    let delay = t.value in
    t.value <- Float.min (t.value *. 2.0) t.max;
    Lwt_unix.sleep delay
end
