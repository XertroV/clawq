type t = {
  mutable history : Provider.message list;
  config : Runtime_config.t;
  system_prompt : string;
}

let max_history = 50

let create ~config =
  {
    history = [];
    config;
    system_prompt =
      "You are clawq, a helpful AI assistant. Answer questions clearly and \
       concisely.";
  }

let turn agent ~user_message =
  let open Lwt.Syntax in
  agent.history <-
    { Provider.role = "user"; content = user_message } :: agent.history;
  let messages =
    { Provider.role = "system"; content = agent.system_prompt }
    :: List.rev agent.history
  in
  let* response = Provider.complete ~config:agent.config ~messages in
  agent.history <-
    { Provider.role = "assistant"; content = response.content }
    :: agent.history;
  let len = List.length agent.history in
  if len > max_history then
    agent.history <- List.filteri (fun i _ -> i < max_history) agent.history;
  Lwt.return response.content
