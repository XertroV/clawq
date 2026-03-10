let skip_kinds =
  [
    "anthropic";
    "gemini";
    "deepseek";
    "cohere";
    "mistral";
    "kimi";
    "zai";
    "minimax";
    "mimo";
  ]

let default_base_url_for_kind = function
  | "groq" -> "https://api.groq.com/openai"
  | "openrouter" -> "https://openrouter.ai/api"
  | "ollama" -> "http://localhost:11434"
  | _ -> "https://api.openai.com"

let should_skip_provider (pc : Runtime_config.provider_config) =
  match pc.kind with Some k -> List.mem k skip_kinds | None -> pc.api_key = ""

let is_ollama (pc : Runtime_config.provider_config) =
  match pc.kind with Some "ollama" -> true | _ -> false

let get_base_url (pc : Runtime_config.provider_config) =
  match pc.base_url with
  | Some u -> u
  | None -> (
      match pc.kind with
      | Some k -> default_base_url_for_kind k
      | None -> "https://api.openai.com")

let check_ttl_hours ~db ~provider ~hours =
  let sql =
    "SELECT MAX(fetched_at) FROM models_cache WHERE provider = ? AND \
     fetched_at > datetime('now', ?)"
  in
  let stmt = Sqlite3.prepare db sql in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize stmt))
    (fun () ->
      ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT provider));
      ignore
        (Sqlite3.bind stmt 2
           (Sqlite3.Data.TEXT (Printf.sprintf "-%d hours" hours)));
      match Sqlite3.step stmt with
      | Sqlite3.Rc.ROW -> (
          match Sqlite3.column stmt 0 with
          | Sqlite3.Data.NULL -> false
          | Sqlite3.Data.TEXT s when s = "" -> false
          | _ -> true)
      | _ -> false)

let upsert_models ~db ~provider models =
  let sql =
    "INSERT OR REPLACE INTO models_cache (provider, model_id, fetched_at) \
     VALUES (?, ?, datetime('now'))"
  in
  let count = ref 0 in
  (try
     let stmt = Sqlite3.prepare db sql in
     Fun.protect
       ~finally:(fun () -> ignore (Sqlite3.finalize stmt))
       (fun () ->
         List.iter
           (fun model_id ->
             ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT provider));
             ignore (Sqlite3.bind stmt 2 (Sqlite3.Data.TEXT model_id));
             (match Sqlite3.step stmt with
             | Sqlite3.Rc.DONE -> incr count
             | rc ->
                 Logs.warn (fun m ->
                     m "models_cache upsert failed: %s"
                       (Sqlite3.Rc.to_string rc)));
             ignore (Sqlite3.reset stmt))
           models)
   with exn ->
     Logs.warn (fun m ->
         m "models_cache upsert error: %s" (Printexc.to_string exn)));
  !count

let fetch_openai_models ~base_url ~api_key =
  let open Lwt.Syntax in
  let uri = base_url ^ "/v1/models" in
  let headers = [ ("Authorization", "Bearer " ^ api_key) ] in
  let* status, body = Http_client.get ~uri ~headers in
  if status = 200 then
    try
      let json = Yojson.Safe.from_string body in
      let open Yojson.Safe.Util in
      let data = json |> member "data" |> to_list in
      let ids =
        List.filter_map
          (fun m -> try Some (m |> member "id" |> to_string) with _ -> None)
          data
      in
      Lwt.return (Ok ids)
    with exn ->
      Lwt.return
        (Error (Printf.sprintf "parse error: %s" (Printexc.to_string exn)))
  else Lwt.return (Error (Printf.sprintf "HTTP %d" status))

let fetch_ollama_models ~base_url =
  let open Lwt.Syntax in
  let uri = base_url ^ "/api/tags" in
  let* status, body = Http_client.get ~uri ~headers:[] in
  if status = 200 then
    try
      let json = Yojson.Safe.from_string body in
      let open Yojson.Safe.Util in
      let models = json |> member "models" |> to_list in
      let names =
        List.filter_map
          (fun m -> try Some (m |> member "name" |> to_string) with _ -> None)
          models
      in
      Lwt.return (Ok names)
    with exn ->
      Lwt.return
        (Error (Printf.sprintf "parse error: %s" (Printexc.to_string exn)))
  else Lwt.return (Error (Printf.sprintf "HTTP %d" status))

let refresh_provider ~db ~provider_name
    ~(provider_config : Runtime_config.provider_config) =
  let open Lwt.Syntax in
  if should_skip_provider provider_config then Lwt.return (Ok 0)
  else
    let base_url = get_base_url provider_config in
    let* result =
      if is_ollama provider_config then fetch_ollama_models ~base_url
      else fetch_openai_models ~base_url ~api_key:provider_config.api_key
    in
    match result with
    | Error e ->
        Logs.warn (fun m ->
            m "model_discovery: %s refresh failed: %s" provider_name e);
        Lwt.return (Error e)
    | Ok model_ids ->
        let count = upsert_models ~db ~provider:provider_name model_ids in
        Logs.info (fun m ->
            m "model_discovery: %s refreshed %d models" provider_name count);
        Lwt.return (Ok count)

let maybe_refresh ?db ?(force = false) ~(config : Runtime_config.t) () =
  let open Lwt.Syntax in
  match db with
  | None ->
      Logs.debug (fun m -> m "model_discovery: no db handle, skipping refresh");
      Lwt.return_unit
  | Some db ->
      let providers = config.providers in
      let* () =
        Lwt_list.iter_s
          (fun (name, pc) ->
            if should_skip_provider pc then Lwt.return_unit
            else
              let fresh =
                (not force) && check_ttl_hours ~db ~provider:name ~hours:12
              in
              if fresh then (
                Logs.debug (fun m ->
                    m "model_discovery: %s cache fresh, skipping" name);
                Lwt.return_unit)
              else
                let* _ =
                  Lwt.catch
                    (fun () ->
                      refresh_provider ~db ~provider_name:name
                        ~provider_config:pc)
                    (fun exn ->
                      Logs.warn (fun m ->
                          m "model_discovery: %s error: %s" name
                            (Printexc.to_string exn));
                      Lwt.return (Error "exception"))
                in
                Lwt.return_unit)
          providers
      in
      Lwt.return_unit
