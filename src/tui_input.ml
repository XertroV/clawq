(* tui_input.ml — Terminal input helpers: key reading, line input, secrets *)

(* ── Key type ──────────────────────────────────────────────────────── *)

type key =
  | Enter
  | Backspace
  | Escape
  | Up
  | Down
  | Right
  | Left
  | Tab
  | Ctrl_c
  | Char of char

(* ── Raw mode primitive ────────────────────────────────────────────── *)

let with_raw_mode ?(isig = true) f =
  let attr = Unix.tcgetattr Unix.stdin in
  let raw =
    {
      attr with
      Unix.c_echo = false;
      c_icanon = false;
      c_isig = isig;
      c_vmin = 1;
      c_vtime = 0;
    }
  in
  Unix.tcsetattr Unix.stdin Unix.TCSAFLUSH raw;
  let restore () = Unix.tcsetattr Unix.stdin Unix.TCSAFLUSH attr in
  Fun.protect ~finally:restore (fun () -> f ())

(* ── Low-level byte reading ────────────────────────────────────────── *)

exception Eof

let read_byte_raw buf =
  let n = Unix.read Unix.stdin buf 0 1 in
  if n = 0 then raise Eof;
  Bytes.get buf 0

(* ── Escape sequence parsing ──────────────────────────────────────── *)

let has_input_ready () =
  try
    let ready, _, _ = Unix.select [ Unix.stdin ] [] [] 0.05 in
    ready <> []
  with Unix.Unix_error (Unix.EINTR, _, _) -> false

let read_key_raw () =
  let buf = Bytes.create 1 in
  let c = read_byte_raw buf in
  if c = '\027' then begin
    (* ESC received — check if part of an escape sequence *)
    if not (has_input_ready ()) then Escape
    else
      let c2 = read_byte_raw buf in
      match c2 with
      | '[' -> (
          (* CSI sequence: read parameter bytes then final byte *)
          let rec eat_csi () =
            let c3 = read_byte_raw buf in
            let code = Char.code c3 in
            if code >= 0x40 && code <= 0x7E then c3 else eat_csi ()
          in
          let final = eat_csi () in
          match final with
          | 'A' -> Up
          | 'B' -> Down
          | 'C' -> Right
          | 'D' -> Left
          | 'H' -> Char '\000' (* Home — ignore *)
          | 'F' -> Char '\000' (* End — ignore *)
          | '~' -> Char '\000' (* Delete/Insert/PgUp/PgDn — ignore *)
          | _ -> Char '\000')
      | 'O' ->
          (* SS3 sequence: arrows or F1-F4 on some terminals *)
          if has_input_ready () then begin
            let c3 = read_byte_raw buf in
            match c3 with
            | 'A' -> Up
            | 'B' -> Down
            | 'C' -> Right
            | 'D' -> Left
            | _ -> Char '\000' (* F1-F4 etc. — ignore *)
          end
          else Escape
      | _ ->
          (* ESC followed by unknown byte — discard both *)
          Char '\000'
  end
  else if c = '\n' || c = '\r' then Enter
  else if c = '\127' || c = '\b' then Backspace
  else if c = '\t' then Tab
  else if c = '\003' then Ctrl_c
  else if c >= ' ' then Char c
  else Char '\000' (* Other control chars — ignore *)

(* ── Public key reader (manages raw mode) ─────────────────────────── *)

let read_key ?(isig = true) () =
  with_raw_mode ~isig (fun () ->
      let rec loop () =
        let k = read_key_raw () in
        (* Filter out sentinel null chars from ignored sequences *)
        if k = Char '\000' then loop () else k
      in
      loop ())

(* ── Shared line-reading core ─────────────────────────────────────── *)

let read_line_core ~echo_char prompt =
  Printf.printf "%s" prompt;
  flush stdout;
  let buf = Buffer.create 64 in
  let result = ref None in
  with_raw_mode (fun () ->
      (try
         while true do
           let k = read_key_raw () in
           match k with
           | Enter -> raise Exit
           | Ctrl_c ->
               result := Some `Interrupted;
               raise Exit
           | Backspace when Buffer.length buf > 0 ->
               let len = Buffer.length buf in
               let contents = Buffer.contents buf in
               Buffer.clear buf;
               Buffer.add_string buf (String.sub contents 0 (len - 1));
               Printf.printf "\b \b";
               flush stdout
           | Char c when c > '\000' ->
               Buffer.add_char buf c;
               (match echo_char with
               | Some ch -> Printf.printf "%s" ch
               | None -> Printf.printf "%c" c);
               flush stdout
           | _ -> () (* Ignore arrows, escape, tab, etc. *)
         done
       with
      | Exit -> ()
      | Eof -> ());
      Printf.printf "\n";
      flush stdout);
  (Buffer.contents buf, !result)

(* ── Public line readers ──────────────────────────────────────────── *)

let read_line_clean prompt =
  if not (Unix.isatty Unix.stdin) then input_line stdin
  else
    let s, _ = read_line_core ~echo_char:None prompt in
    s

let read_secret prompt =
  if not (Unix.isatty Unix.stdin) then
    Error "Cannot prompt for secret: stdin is not a terminal"
  else
    let s, interrupted =
      read_line_core ~echo_char:(Some "\xE2\x80\xA2") prompt
    in
    if interrupted = Some `Interrupted then Error "Interrupted."
    else
      let trimmed = String.trim s in
      if trimmed = "" then Error "No value entered." else Ok trimmed

(* ── Utilities ────────────────────────────────────────────────────── *)

let redact s =
  let len = String.length s in
  if len <= 8 then String.make len '*'
  else String.sub s 0 4 ^ "..." ^ String.sub s (len - 4) 4
