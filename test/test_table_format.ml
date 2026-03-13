let test_word_wrap_short () =
  let lines = Table_format.word_wrap 40 "hello world" in
  Alcotest.(check (list string)) "fits in one line" [ "hello world" ] lines

let test_word_wrap_long () =
  let lines = Table_format.word_wrap 10 "one two three four" in
  Alcotest.(check (list string))
    "wraps at width"
    [ "one two"; "three four" ]
    lines

let test_word_wrap_exact () =
  let lines = Table_format.word_wrap 5 "hello world" in
  Alcotest.(check (list string))
    "each word on own line" [ "hello"; "world" ] lines

let test_word_wrap_zero_width () =
  let lines = Table_format.word_wrap 0 "hello" in
  Alcotest.(check (list string)) "zero width returns as-is" [ "hello" ] lines

let test_pad_left () =
  let s = Table_format.pad Left 10 "hello" in
  Alcotest.(check string) "left padded" "hello     " s

let test_pad_right () =
  let s = Table_format.pad Right 10 "42" in
  Alcotest.(check string) "right padded" "        42" s

let test_pad_exact () =
  let s = Table_format.pad Left 5 "hello" in
  Alcotest.(check string) "exact width" "hello" s

let test_render_basic () =
  let columns =
    Table_format.
      [
        { header = "NAME"; align = Left; min_width = 4; flex = false };
        { header = "VALUE"; align = Left; min_width = 5; flex = false };
      ]
  in
  let rows = [ [ "foo"; "bar" ]; [ "longer"; "x" ] ] in
  let result = Table_format.render ~max_width:80 columns rows in
  Alcotest.(check bool) "contains header" true (String.length result > 0);
  Alcotest.(check bool)
    "contains NAME" true
    (try
       ignore (Str.search_forward (Str.regexp_string "NAME") result 0);
       true
     with Not_found -> false);
  Alcotest.(check bool)
    "contains foo" true
    (try
       ignore (Str.search_forward (Str.regexp_string "foo") result 0);
       true
     with Not_found -> false);
  Alcotest.(check bool)
    "contains longer" true
    (try
       ignore (Str.search_forward (Str.regexp_string "longer") result 0);
       true
     with Not_found -> false)

let test_render_with_flex_column () =
  let columns =
    Table_format.
      [
        { header = "ID"; align = Right; min_width = 2; flex = false };
        { header = "DESC"; align = Left; min_width = 5; flex = true };
      ]
  in
  let rows = [ [ "1"; "a short description" ]; [ "42"; "another one" ] ] in
  let result = Table_format.render ~max_width:40 columns rows in
  Alcotest.(check bool) "renders without error" true (String.length result > 0)

let test_render_word_wraps_flex () =
  let columns =
    Table_format.
      [
        { header = "N"; align = Left; min_width = 1; flex = false };
        { header = "TEXT"; align = Left; min_width = 5; flex = true };
      ]
  in
  let rows = [ [ "x"; "one two three four five six seven eight nine ten" ] ] in
  let result = Table_format.render ~max_width:30 columns rows in
  let lines = String.split_on_char '\n' result in
  Alcotest.(check bool)
    "flex column wraps to multiple lines" true
    (List.length lines > 2)

let test_render_empty_rows () =
  let columns =
    Table_format.
      [
        { header = "A"; align = Left; min_width = 1; flex = false };
        { header = "B"; align = Left; min_width = 1; flex = false };
      ]
  in
  let result = Table_format.render ~max_width:80 columns [] in
  let lines = String.split_on_char '\n' result in
  Alcotest.(check int) "header only" 1 (List.length lines)

let tests =
  [
    Alcotest.test_case "word_wrap short text" `Quick test_word_wrap_short;
    Alcotest.test_case "word_wrap long text" `Quick test_word_wrap_long;
    Alcotest.test_case "word_wrap exact width" `Quick test_word_wrap_exact;
    Alcotest.test_case "word_wrap zero width" `Quick test_word_wrap_zero_width;
    Alcotest.test_case "pad left" `Quick test_pad_left;
    Alcotest.test_case "pad right" `Quick test_pad_right;
    Alcotest.test_case "pad exact" `Quick test_pad_exact;
    Alcotest.test_case "render basic" `Quick test_render_basic;
    Alcotest.test_case "render with flex" `Quick test_render_with_flex_column;
    Alcotest.test_case "render wraps flex" `Quick test_render_word_wraps_flex;
    Alcotest.test_case "render empty rows" `Quick test_render_empty_rows;
  ]
