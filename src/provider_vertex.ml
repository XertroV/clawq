(* Provider implementation for Google Vertex AI
   Endpoint: https://{location}-aiplatform.googleapis.com/v1/projects/{project_id}/locations/{location}/publishers/google/models/{model}:generateContent
   Auth: OAuth2 Bearer token from service account JWT (RS256)
   TODO: Full JWT signing not yet implemented - requires RSA private key parsing *)

let default_location = "us-central1"

let get_project_id (provider : Runtime_config.provider_config) =
  match provider.project_id with
  | Some pid -> pid
  | None -> (
      try Sys.getenv "GOOGLE_CLOUD_PROJECT"
      with Not_found -> (
        try Sys.getenv "GCLOUD_PROJECT" with Not_found -> ""))

let get_location (provider : Runtime_config.provider_config) =
  match provider.location with Some loc -> loc | None -> default_location

let vertex_endpoint ~project_id ~location ~model =
  Printf.sprintf
    "https://%s-aiplatform.googleapis.com/v1/projects/%s/locations/%s/publishers/google/models/%s:generateContent"
    location project_id location model

let vertex_stream_endpoint ~project_id ~location ~model =
  Printf.sprintf
    "https://%s-aiplatform.googleapis.com/v1/projects/%s/locations/%s/publishers/google/models/%s:streamGenerateContent?alt=sse"
    location project_id location model

(* TODO: not yet implemented - JWT RS256 signing for service account auth.
   For now, attempt to use GOOGLE_APPLICATION_CREDENTIALS via gcloud ADC token
   or accept a pre-generated token in the api_key field. *)
let get_access_token (provider : Runtime_config.provider_config) =
  let open Lwt.Syntax in
  (* If api_key is set and looks like an OAuth token, use it directly *)
  if provider.api_key <> "" && String.length provider.api_key > 20 then
    Lwt.return provider.api_key
  else begin
    (* TODO: implement proper service account JWT flow *)
    (* For now fall back to GOOGLE_APPLICATION_CREDENTIALS / gcloud token *)
    Logs.warn (fun m ->
        m "Vertex: no access token configured; JWT flow not yet implemented");
    Lwt.return ""
  end

(* Reuse Gemini content format since Vertex uses identical structure *)
let messages_to_contents = Provider_gemini.messages_to_gemini_contents
let extract_system_prompt = Provider_gemini.extract_system_prompt
let tools_to_vertex_json = Provider_gemini.tools_to_gemini_json

let make_request_body ~config ~messages ~tools =
  let contents = messages_to_contents messages in
  let system_prompt = extract_system_prompt messages in
  let body_fields =
    [
      ("contents", `List contents);
      ( "generationConfig",
        `Assoc
          [
            ( "temperature",
              `Float (max 1e-8 config.Runtime_config.default_temperature) );
            ("maxOutputTokens", `Int 8192);
          ] );
    ]
  in
  let body_fields =
    if system_prompt <> "" then
      body_fields
      @ [
          ( "systemInstruction",
            `Assoc
              [
                ("parts", `List [ `Assoc [ ("text", `String system_prompt) ] ]);
              ] );
        ]
    else body_fields
  in
  let body_fields =
    match tools_to_vertex_json tools with
    | Some t -> body_fields @ [ ("tools", t) ]
    | None -> body_fields
  in
  `Assoc body_fields |> Yojson.Safe.to_string

let parse_response = Provider_gemini.parse_gemini_response

let complete ~(config : Runtime_config.t)
    ~(provider : Runtime_config.provider_config) ~model ~messages ?tools () =
  let open Lwt.Syntax in
  let project_id = get_project_id provider in
  let location = get_location provider in
  if project_id = "" then
    Lwt.fail_with
      "Vertex: project_id not configured (set in provider config or \
       GOOGLE_CLOUD_PROJECT env)"
  else
    let uri = vertex_endpoint ~project_id ~location ~model in
    let body = make_request_body ~config ~messages ~tools in
    let* token = get_access_token provider in
    let headers =
      if token <> "" then [ ("Authorization", "Bearer " ^ token) ] else []
    in
    Logs.info (fun m ->
        m "Vertex request to %s model=%s msgs=%d" uri model
          (List.length messages));
    let* status, response_body = Http_client.post_json ~uri ~headers ~body in
    if status < 200 || status >= 300 then
      Lwt.fail_with
        (Printf.sprintf "Vertex API error (HTTP %d): %s" status response_body)
    else
      match parse_response response_body model with
      | Ok resp -> Lwt.return resp
      | Error msg -> Lwt.fail_with msg

let complete_streaming ~(config : Runtime_config.t)
    ~(provider : Runtime_config.provider_config) ~model ~messages ?tools
    ~on_chunk () =
  let open Lwt.Syntax in
  let project_id = get_project_id provider in
  let location = get_location provider in
  if project_id = "" then
    Lwt.fail_with
      "Vertex: project_id not configured (set in provider config or \
       GOOGLE_CLOUD_PROJECT env)"
  else
    let uri = vertex_stream_endpoint ~project_id ~location ~model in
    let body = make_request_body ~config ~messages ~tools in
    let* token = get_access_token provider in
    let headers =
      if token <> "" then [ ("Authorization", "Bearer " ^ token) ] else []
    in
    Logs.info (fun m ->
        m "Vertex stream request to %s model=%s msgs=%d" uri model
          (List.length messages));
    let* status, stream = Http_client.post_stream ~uri ~headers ~body in
    if status < 200 || status >= 300 then begin
      let* chunks = Lwt_stream.to_list stream in
      let response_body = String.concat "" chunks in
      Lwt.fail_with
        (Printf.sprintf "Vertex API error (HTTP %d): %s" status response_body)
    end
    else
      (* Reuse Gemini SSE parsing logic - identical format *)
      let buf = Buffer.create 256 in
      let content_acc = Buffer.create 1024 in
      let resp_model = ref model in
      let usage_acc = ref None in
      let tool_calls_acc : Provider.tool_call list ref = ref [] in
      let tc_counter = ref 0 in
      let process_line line =
        let prefix = "data: " in
        let plen = String.length prefix in
        if String.length line >= plen && String.sub line 0 plen = prefix then begin
          let data = String.sub line plen (String.length line - plen) in
          if data = "[DONE]" then begin
            let* () = on_chunk Provider.Done in
            Lwt.return_unit
          end
          else
            try
              let json = Yojson.Safe.from_string data in
              let open Yojson.Safe.Util in
              (try resp_model := json |> member "modelVersion" |> to_string
               with _ -> ());
              (try
                 let u = json |> member "usageMetadata" in
                 let pt = u |> member "promptTokenCount" |> to_int in
                 let ct = u |> member "candidatesTokenCount" |> to_int in
                 usage_acc := Some (pt, ct)
               with _ -> ());
              let parts =
                try
                  json |> member "candidates" |> index 0 |> member "content"
                  |> member "parts" |> to_list
                with _ -> []
              in
              Lwt_list.iter_s
                (fun part ->
                  let* () =
                    try
                      let text = part |> member "text" |> to_string in
                      if text <> "" then begin
                        Buffer.add_string content_acc text;
                        on_chunk (Provider.Delta text)
                      end
                      else Lwt.return_unit
                    with _ -> Lwt.return_unit
                  in
                  (try
                     let fc = part |> member "functionCall" in
                     let name = fc |> member "name" |> to_string in
                     let args = fc |> member "args" in
                     let arguments = Yojson.Safe.to_string args in
                     let idx = !tc_counter in
                     incr tc_counter;
                     let id = Printf.sprintf "vertex_%s_%d" name idx in
                     tool_calls_acc :=
                       !tool_calls_acc
                       @ [ { Provider.id; function_name = name; arguments } ]
                   with _ -> ());
                  Lwt.return_unit)
                parts
            with _ -> Lwt.return_unit
        end
        else Lwt.return_unit
      in
      let process_buffer () =
        let s = Buffer.contents buf in
        Buffer.clear buf;
        let lines = String.split_on_char '\n' s in
        let rec process_lines = function
          | [] -> Lwt.return_unit
          | [ last ] ->
              Buffer.add_string buf last;
              Lwt.return_unit
          | line :: rest ->
              let line =
                if
                  String.length line > 0 && line.[String.length line - 1] = '\r'
                then String.sub line 0 (String.length line - 1)
                else line
              in
              let* () =
                if line <> "" then process_line line else Lwt.return_unit
              in
              process_lines rest
        in
        process_lines lines
      in
      let* () =
        Lwt_stream.iter_s
          (fun chunk ->
            Buffer.add_string buf chunk;
            process_buffer ())
          stream
      in
      let remaining = Buffer.contents buf in
      let* () =
        if remaining <> "" then process_line remaining else Lwt.return_unit
      in
      let content = Buffer.contents content_acc in
      let final_model = !resp_model in
      if !tool_calls_acc <> [] then
        Lwt.return
          (Provider.ToolCalls
             {
               calls = !tool_calls_acc;
               model = final_model;
               usage = !usage_acc;
             })
      else
        Lwt.return
          (Provider.Text { content; model = final_model; usage = !usage_acc })
