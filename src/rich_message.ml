type button = { label : string; callback_id : string }
type button_row = button list

type t =
  | Text of string
  | TextWithButtons of { text : string; button_rows : button_row list }
  | Poll of { question : string; options : string list; allows_multiple : bool }

type send_result = { message_id : string; callback_ids : string list }

let to_fallback_text = function
  | Text s -> s
  | TextWithButtons { text; button_rows } ->
      let idx = ref 0 in
      let lines =
        List.concat_map
          (fun row ->
            List.map
              (fun (btn : button) ->
                incr idx;
                Printf.sprintf "%d. %s" !idx btn.label)
              row)
          button_rows
      in
      text ^ "\n\n" ^ String.concat "\n" lines
  | Poll { question; options; _ } ->
      let lines =
        List.mapi (fun i opt -> Printf.sprintf "%d. %s" (i + 1) opt) options
      in
      question ^ "\n\n" ^ String.concat "\n" lines
