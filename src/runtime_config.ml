type provider_config = { api_key : string; base_url : string option; default_model : string option }

type agent_defaults = {
  primary_model : string;
  model_priority : string list;
  system_prompt : string;
  max_tool_iterations : int;
}

type telegram_account = { bot_token : string; allow_from : string list }

type telegram_config = { accounts : (string * telegram_account) list }

type channel_config = { cli : bool; telegram : telegram_config option }

type gateway_config = { host : string; port : int; require_pairing : bool }

type memory_config = { backend : string; search_enabled : bool; db_path : string }

type security_config = {
  workspace_only : bool;
  audit_enabled : bool;
  tools_enabled : bool;
  encrypt_secrets : bool;
}

type stt_config = {
  provider : string;
  model : string;
  language : string option;
}

type zai_mcp_config = {
  web_search_enabled : bool;
  web_reader_enabled : bool;
}

type cloudflare_tunnel_config = {
  api_token : string;
  account_id : string option;
  tunnel_id : string option;
  tunnel_name : string option;
  hostname : string option;
  config_path : string option;
  credentials_path : string option;
  ingress_service : string option;
}

type tunnel_config = {
  enabled : bool;
  provider : string;
  cloudflare : cloudflare_tunnel_config option;
}

let zai_coding_provider_name = "zai_coding"

let zai_coding_provider : provider_config = {
  api_key = "";
  base_url = Some "https://api.z.ai/api/coding/paas/v4";
  default_model = Some "glm-5";
}

let default_zai_mcp : zai_mcp_config = {
  web_search_enabled = true;
  web_reader_enabled = true;
}

let default_cloudflare_tunnel : cloudflare_tunnel_config = {
  api_token = "";
  account_id = None;
  tunnel_id = None;
  tunnel_name = Some "clawq";
  hostname = None;
  config_path = None;
  credentials_path = None;
  ingress_service = Some "http://127.0.0.1:3000";
}

let default_tunnel : tunnel_config = {
  enabled = false;
  provider = "cloudflare";
  cloudflare = Some default_cloudflare_tunnel;
}

type t = {
  default_temperature : float;
  default_provider : string option;
  providers : (string * provider_config) list;
  agent_defaults : agent_defaults;
  channels : channel_config;
  gateway : gateway_config;
  memory : memory_config;
  security : security_config;
  stt : stt_config option;
  zai_mcp : zai_mcp_config option;
  tunnel : tunnel_config option;
}

let default =
  {
    default_temperature = 0.7;
    default_provider = None;
    providers = [];
    agent_defaults = {
      primary_model = "openai/gpt-4o";
      model_priority = [ "openai/gpt-4o" ];
      system_prompt = "You are clawq, a helpful AI assistant. Answer questions clearly and concisely.";
      max_tool_iterations = 10;
    };
    channels = { cli = true; telegram = None };
    gateway = { host = "127.0.0.1"; port = 3000; require_pairing = false };
    memory = { backend = "sqlite"; search_enabled = false; db_path = "" };
    security = { workspace_only = true; audit_enabled = false; tools_enabled = true; encrypt_secrets = false };
    stt = None;
    zai_mcp = Some default_zai_mcp;
    tunnel = Some default_tunnel;
  }

let is_key_set key =
  key <> "" && not (String.length key > 4 && String.sub key 0 4 = "YOUR")

let with_zai_coding_provider providers =
  match List.assoc_opt zai_coding_provider_name providers with
  | Some _ -> providers
  | None -> providers @ [ (zai_coding_provider_name, zai_coding_provider) ]

let effective_primary_model (ad : agent_defaults) =
  match ad.model_priority with
  | model :: _ -> model
  | [] -> ad.primary_model

let to_json (cfg : t) : Yojson.Safe.t =
  let opt_string = function Some s -> `String s | None -> `Null in
  let provider_json (p : provider_config) =
    let fields = [ ("api_key", `String p.api_key) ] in
    let fields = match p.base_url with
      | Some url -> fields @ [ ("base_url", `String url) ]
      | None -> fields
    in
    let fields = match p.default_model with
      | Some m -> fields @ [ ("default_model", `String m) ]
      | None -> fields
    in
    `Assoc fields
  in
  let ad = cfg.agent_defaults in
  let telegram_json = match cfg.channels.telegram with
    | None -> `Null
    | Some tg ->
      `Assoc [ ("accounts",
        `Assoc (List.map (fun (name, (acct : telegram_account)) ->
          (name, `Assoc [
            ("bot_token", `String acct.bot_token);
            ("allow_from", `List (List.map (fun s -> `String s) acct.allow_from));
          ])) tg.accounts)) ]
  in
  let stt_json = match cfg.stt with
    | None -> `Null
    | Some s ->
      `Assoc ([ ("provider", `String s.provider); ("model", `String s.model) ]
              @ (match s.language with Some l -> [ ("language", `String l) ] | None -> []))
  in
  let zai_mcp_json = match cfg.zai_mcp with
    | None -> `Null
    | Some z ->
      `Assoc [
        ("web_search_enabled", `Bool z.web_search_enabled);
        ("web_reader_enabled", `Bool z.web_reader_enabled);
      ]
  in
  let tunnel_json =
    match cfg.tunnel with
    | None -> `Null
    | Some t ->
      let cloudflare_json =
        match t.cloudflare with
        | None -> `Null
        | Some c ->
          let fields = [ ("api_token", `String c.api_token) ] in
          let fields =
            match c.account_id with
            | Some v -> fields @ [ ("account_id", `String v) ]
            | None -> fields
          in
          let fields =
            match c.tunnel_id with
            | Some v -> fields @ [ ("tunnel_id", `String v) ]
            | None -> fields
          in
          let fields =
            match c.tunnel_name with
            | Some v -> fields @ [ ("tunnel_name", `String v) ]
            | None -> fields
          in
          let fields =
            match c.hostname with
            | Some v -> fields @ [ ("hostname", `String v) ]
            | None -> fields
          in
          let fields =
            match c.config_path with
            | Some v -> fields @ [ ("config_path", `String v) ]
            | None -> fields
          in
          let fields =
            match c.credentials_path with
            | Some v -> fields @ [ ("credentials_path", `String v) ]
            | None -> fields
          in
          let fields =
            match c.ingress_service with
            | Some v -> fields @ [ ("ingress_service", `String v) ]
            | None -> fields
          in
          `Assoc fields
      in
      let fields =
        [
          ("enabled", `Bool t.enabled);
          ("provider", `String t.provider);
        ]
      in
      let fields =
        match cloudflare_json with
        | `Null -> fields
        | j -> fields @ [ ("cloudflare", j) ]
      in
      `Assoc fields
  in
  let fields = [
    ("default_temperature", `Float cfg.default_temperature);
  ] in
  let fields = match cfg.default_provider with
    | Some p -> fields @ [ ("default_provider", `String p) ]
    | None -> fields
  in
  let fields = fields @ [
    ("providers", `Assoc (List.map (fun (name, p) -> (name, provider_json p)) cfg.providers));
    ("agent_defaults", `Assoc [
      ("primary_model", `String (effective_primary_model ad));
      ("model_priority", `List (List.map (fun m -> `String m) ad.model_priority));
      ("system_prompt", `String ad.system_prompt);
      ("max_tool_iterations", `Int ad.max_tool_iterations);
    ]);
    ("channels", `Assoc (
      [ ("cli", `Bool cfg.channels.cli) ]
      @ (match telegram_json with `Null -> [] | j -> [ ("telegram", j) ])
    ));
    ("gateway", `Assoc [
      ("host", `String cfg.gateway.host);
      ("port", `Int cfg.gateway.port);
      ("require_pairing", `Bool cfg.gateway.require_pairing);
    ]);
    ("memory", `Assoc ([
      ("backend", `String cfg.memory.backend);
      ("search_enabled", `Bool cfg.memory.search_enabled);
    ] @ (if cfg.memory.db_path <> "" then [ ("db_path", `String cfg.memory.db_path) ] else [])));
    ("security", `Assoc [
      ("workspace_only", `Bool cfg.security.workspace_only);
      ("audit_enabled", `Bool cfg.security.audit_enabled);
      ("tools_enabled", `Bool cfg.security.tools_enabled);
      ("encrypt_secrets", `Bool cfg.security.encrypt_secrets);
    ]);
  ] in
  let fields = match stt_json with
    | `Null -> fields
    | j -> fields @ [ ("stt", j) ]
  in
  let fields = match zai_mcp_json with
    | `Null -> fields
    | j -> fields @ [ ("zai_mcp", j) ]
  in
  let fields = match tunnel_json with
    | `Null -> fields
    | j -> fields @ [ ("tunnel", j) ]
  in
  ignore opt_string;
  `Assoc fields

let merge_with_coq (coq_cfg : Clawq_core.clawqConfig) (cfg : t) : t =
  let gw = coq_cfg.config_gateway in
  let mem = coq_cfg.config_memory in
  let sec = coq_cfg.config_security in
  {
    cfg with
    default_temperature =
      float_of_int coq_cfg.config_default_temperature /. 100.0;
    agent_defaults = {
      cfg.agent_defaults with
      primary_model = coq_cfg.config_default_model;
      model_priority = [ coq_cfg.config_default_model ];
    };
    gateway =
      {
        host = gw.gateway_host;
        port = gw.gateway_port;
        require_pairing = gw.gateway_require_pairing;
      };
    memory =
      {
        cfg.memory with
        backend = mem.memory_backend;
        search_enabled = mem.memory_search_enabled;
      };
    security =
      {
        cfg.security with
        workspace_only = sec.security_workspace_only_cfg;
        audit_enabled = sec.security_audit_enabled_cfg;
        encrypt_secrets = sec.security_encrypt_secrets_cfg;
      };
  }
