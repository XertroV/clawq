type alignment = Left | Right

type column = {
  header : string;
  align : alignment;
  min_width : int;
  flex : bool;
}

let terminal_width () =
  try
    let ic = Unix.open_process_in "tput cols 2>/dev/null" in
    let w = int_of_string (String.trim (input_line ic)) in
    ignore (Unix.close_process_in ic);
    if w > 20 then Some w else None
  with _ -> None

let word_wrap width text =
  if width <= 0 || String.length text <= width then [ text ]
  else
    let words = String.split_on_char ' ' text in
    let rec build acc line = function
      | [] ->
          let lines = if line = "" then acc else line :: acc in
          List.rev lines
      | w :: rest ->
          if line = "" then build acc w rest
          else
            let candidate = line ^ " " ^ w in
            if String.length candidate <= width then build acc candidate rest
            else build (line :: acc) w rest
    in
    match build [] "" words with [] -> [ "" ] | lines -> lines

let pad align width s =
  let len = String.length s in
  if len >= width then s
  else
    let padding = String.make (width - len) ' ' in
    match align with Left -> s ^ padding | Right -> padding ^ s

let render ?(indent = 2) ?(col_sep = "  ") ?(max_width = 0) columns rows =
  let tw =
    if max_width > 0 then max_width
    else match terminal_width () with Some w -> w | None -> 120
  in
  let n_cols = List.length columns in
  let sep_len = String.length col_sep in
  let fixed_overhead = indent + ((n_cols - 1) * sep_len) in
  let col_widths =
    List.mapi
      (fun i (col : column) ->
        let data_max =
          List.fold_left
            (fun mx row ->
              let cell = try List.nth row i with _ -> "" in
              max mx (String.length cell))
            (String.length col.header) rows
        in
        max col.min_width data_max)
      columns
  in
  let total_fixed =
    List.fold_left2
      (fun acc w (col : column) -> if col.flex then acc else acc + w)
      fixed_overhead col_widths columns
  in
  let flex_cols =
    List.combine col_widths columns
    |> List.filter (fun (_, (col : column)) -> col.flex)
  in
  let final_widths =
    if flex_cols = [] then col_widths
    else
      let remaining = tw - total_fixed in
      let n_flex = List.length flex_cols in
      let per_flex = max 10 (remaining / max 1 n_flex) in
      List.map2
        (fun w (col : column) -> if col.flex then min w per_flex else w)
        col_widths columns
  in
  let indent_str = String.make indent ' ' in
  let format_row cells =
    let wrapped_cells =
      List.mapi
        (fun i cell ->
          let w = try List.nth final_widths i with _ -> 20 in
          let col =
            try List.nth columns i
            with _ ->
              { header = ""; align = Left; min_width = 0; flex = false }
          in
          let lines = if col.flex then word_wrap w cell else [ cell ] in
          (lines, w, col.align))
        cells
    in
    let max_lines =
      List.fold_left
        (fun mx (lines, _, _) -> max mx (List.length lines))
        1 wrapped_cells
    in
    let output_lines = ref [] in
    for line_idx = 0 to max_lines - 1 do
      let parts =
        List.map
          (fun (lines, w, align) ->
            let text =
              if line_idx < List.length lines then List.nth lines line_idx
              else ""
            in
            pad align w text)
          wrapped_cells
      in
      output_lines :=
        (indent_str ^ String.concat col_sep parts) :: !output_lines
    done;
    List.rev !output_lines
  in
  let header_cells = List.map (fun (col : column) -> col.header) columns in
  let header_lines = format_row header_cells in
  let row_lines = List.concat_map format_row rows in
  String.concat "\n" (header_lines @ row_lines)

let render_markdown ?(escape_cell = Fun.id) columns rows =
  let header =
    "| "
    ^ String.concat " | " (List.map (fun (col : column) -> col.header) columns)
    ^ " |"
  in
  let separator =
    "| "
    ^ String.concat " | "
        (List.map
           (fun (col : column) ->
             match col.align with Left -> ":---" | Right -> "---:")
           columns)
    ^ " |"
  in
  let data_rows =
    List.map
      (fun cells ->
        "| " ^ String.concat " | " (List.map escape_cell cells) ^ " |")
      rows
  in
  String.concat "\n" ([ header; separator ] @ data_rows)
