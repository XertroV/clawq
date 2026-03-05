let json_headers =
  Cohttp.Header.of_list [ ("Content-Type", "application/json") ]

let handler _conn req body =
  let open Lwt.Syntax in
  let uri = Cohttp.Request.uri req in
  let path = Uri.path uri in
  let meth = Cohttp.Request.meth req in
  match (meth, path) with
  | `GET, "/health" ->
    let* _ = Cohttp_lwt.Body.drain_body body in
    Cohttp_lwt_unix.Server.respond_string ~status:`OK ~headers:json_headers
      ~body:{|{"status":"ok"}|} ()
  | _ ->
    let* _ = Cohttp_lwt.Body.drain_body body in
    Cohttp_lwt_unix.Server.respond_string ~status:`Not_found
      ~headers:json_headers ~body:{|{"error":"not found"}|} ()

let start ~port ~host:_ =
  let callback = handler in
  let server =
    Cohttp_lwt_unix.Server.create
      ~mode:(`TCP (`Port port))
      (Cohttp_lwt_unix.Server.make ~callback ())
  in
  server
