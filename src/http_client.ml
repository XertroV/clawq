let post_json ~uri ~headers ~body =
  let open Lwt.Syntax in
  let uri = Uri.of_string uri in
  let headers =
    Cohttp.Header.of_list
      (("Content-Type", "application/json") :: headers)
  in
  let body = Cohttp_lwt.Body.of_string body in
  let* response, body = Cohttp_lwt_unix.Client.post ~headers ~body uri in
  let status = Cohttp.Response.status response |> Cohttp.Code.code_of_status in
  let* body_str = Cohttp_lwt.Body.to_string body in
  Lwt.return (status, body_str)

let get ~uri ~headers =
  let open Lwt.Syntax in
  let uri = Uri.of_string uri in
  let headers = Cohttp.Header.of_list headers in
  let* response, body = Cohttp_lwt_unix.Client.get ~headers uri in
  let status = Cohttp.Response.status response |> Cohttp.Code.code_of_status in
  let* body_str = Cohttp_lwt.Body.to_string body in
  Lwt.return (status, body_str)
