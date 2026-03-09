let normalize_path path =
  let parts = String.split_on_char '/' path in
  let is_abs = String.length path > 0 && path.[0] = '/' in
  let rec resolve acc = function
    | [] -> List.rev acc
    | "." :: rest -> resolve acc rest
    | ".." :: rest -> (
        match acc with _ :: tl -> resolve tl rest | [] -> resolve [] rest)
    | "" :: rest -> resolve acc rest
    | part :: rest -> resolve (part :: acc) rest
  in
  let resolved = resolve [] parts in
  let joined = String.concat "/" resolved in
  if is_abs then "/" ^ joined else joined
