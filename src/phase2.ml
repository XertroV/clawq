let deferred_features =
  [
    "Gateway API and pairing-token flow (/health, /pair, /webhook)";
    "Subagent/delegation orchestration manager";
    "Hardware peripheral integrations";
    "Self-update command surface";
    "Tunnel providers beyond Cloudflare";
    "Channel adapters beyond web and telegram";
    "Additional native providers beyond OpenAI-compatible baseline";
  ]

let render () =
  let body =
    deferred_features
    |> List.mapi (fun i item -> Printf.sprintf "%d. %s" (i + 1) item)
    |> String.concat "\n"
  in
  "Deferred to Phase 2:\n" ^ body
