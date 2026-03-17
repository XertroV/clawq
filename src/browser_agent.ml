(* browser_agent.ml — LLM-powered browser instruction decomposition *)

type step = {
  action : string;
  params : (string * string) list;
  wait_after_s : float;
  description : string;
}

type browse_result = {
  steps_executed : (step * string) list;
  error : string option;
  extracted_data : string option;
  final_url : string;
  elapsed_s : float;
}

let planner_system_prompt =
  {|You are a browser automation planner. Given a page snapshot and instruction, produce a JSON array of steps to execute.

Available actions and their parameters:
- navigate: url (string)
- click: selector (CSS selector string)
- type: selector, text
- wait: selector, timeout (optional, default "10")
- content: selector (optional)
- evaluate: expression (JavaScript code)
- screenshot: (no required params)

Output format: JSON array of objects, each with:
- "action": string (one of the above)
- "params": object of parameter key-value pairs
- "wait_after_s": number (seconds to wait after this step, typically 0.5-2.0)
- "description": string (brief human-readable description)

Rules:
1. Use CSS selectors. Prefer #id selectors, then [name=...], then tag-based selectors.
2. Keep the plan minimal — fewest steps to achieve the goal.
3. After form submissions or clicks that trigger navigation, add a wait step.
4. Output ONLY the JSON array, no markdown fences, no commentary.|}

let parse_steps json_str =
  try
    let json = Yojson.Safe.from_string json_str in
    let open Yojson.Safe.Util in
    let steps =
      json |> to_list
      |> List.map (fun step ->
          let action = step |> member "action" |> to_string in
          let params =
            try
              step |> member "params" |> to_assoc
              |> List.filter_map (fun (k, v) ->
                  try Some (k, to_string v) with _ -> None)
            with _ -> []
          in
          let wait_after_s =
            try step |> member "wait_after_s" |> to_float with _ -> 0.0
          in
          let description =
            try step |> member "description" |> to_string with _ -> action
          in
          { action; params; wait_after_s; description })
    in
    Ok steps
  with exn ->
    Error (Printf.sprintf "Failed to parse steps: %s" (Printexc.to_string exn))

let execute_step (browser : Cdp_client.t) (step : step) =
  let open Lwt.Syntax in
  let get p = List.assoc_opt p step.params in
  let result =
    match step.action with
    | "navigate" -> (
        match get "url" with
        | Some url ->
            let* () = Cdp_client.navigate browser ~url () in
            Lwt.return (Ok "navigated")
        | None -> Lwt.return (Error "navigate requires 'url' parameter"))
    | "click" -> (
        match get "selector" with
        | Some selector -> (
            let* r = Cdp_client.click browser ~selector () in
            match r with
            | Ok s -> Lwt.return (Ok s)
            | Error e -> Lwt.return (Error e))
        | None -> Lwt.return (Error "click requires 'selector' parameter"))
    | "type" -> (
        match (get "selector", get "text") with
        | Some selector, Some text -> (
            let* r = Cdp_client.fill browser ~selector ~text () in
            match r with
            | Ok s -> Lwt.return (Ok s)
            | Error e -> Lwt.return (Error e))
        | _ ->
            Lwt.return (Error "type requires 'selector' and 'text' parameters"))
    | "wait" -> (
        match get "selector" with
        | Some selector -> (
            let timeout_s =
              try
                match get "timeout" with
                | Some s -> float_of_string s
                | None -> 10.0
              with _ -> 10.0
            in
            let* r =
              Cdp_client.wait_for_selector browser ~selector ~timeout_s ()
            in
            match r with
            | Ok () -> Lwt.return (Ok "found")
            | Error e -> Lwt.return (Error e))
        | None -> Lwt.return (Error "wait requires 'selector' parameter"))
    | "content" ->
        let* content =
          Cdp_client.get_content browser ?selector:(get "selector") ()
        in
        Lwt.return (Ok content)
    | "evaluate" -> (
        match get "expression" with
        | Some expression -> (
            let* r = Cdp_client.evaluate browser ~expression () in
            match r with
            | Ok s -> Lwt.return (Ok s)
            | Error e -> Lwt.return (Error e))
        | None -> Lwt.return (Error "evaluate requires 'expression' parameter"))
    | "screenshot" ->
        let* path = Cdp_client.screenshot browser () in
        Lwt.return (Ok ("Screenshot saved: " ^ path))
    | other -> Lwt.return (Error (Printf.sprintf "Unknown action: %s" other))
  in
  let* r = result in
  let* () =
    if step.wait_after_s > 0.0 then Lwt_unix.sleep step.wait_after_s
    else Lwt.return_unit
  in
  Lwt.return r

let execute_instruction ~(config : Runtime_config.t) ~(browser : Cdp_client.t)
    ~instructions ?extract_schema:_ () =
  let open Lwt.Syntax in
  let start_time = Unix.gettimeofday () in
  (* Get page state *)
  let* a11y = Cdp_client.get_accessibility_tree browser () in
  let* url_result =
    Cdp_client.evaluate browser
      ~expression:"document.title + ' - ' + location.href" ()
  in
  let page_state =
    match url_result with Ok s -> s | Error _ -> "(unknown page)"
  in
  let user_prompt =
    Printf.sprintf "Page: %s\n\nInteractive elements:\n%s\n\nInstruction: %s"
      page_state a11y instructions
  in
  (* Call LLM to plan steps *)
  let pm = config.browser.agent_model in
  let override = Summarizer.summarizer_config_for ~config pm in
  let messages =
    [
      Provider.make_message ~role:"system" ~content:planner_system_prompt;
      Provider.make_message ~role:"user" ~content:user_prompt;
    ]
  in
  Lwt.catch
    (fun () ->
      let* response = Provider.complete ~config:override ~messages () in
      let plan_text =
        match response with
        | Provider.Text { content; _ } -> String.trim content
        | Provider.ToolCalls _ -> "[]"
      in
      (* Strip markdown fences if present *)
      let plan_text =
        let s = String.trim plan_text in
        if String.length s > 6 && String.sub s 0 3 = "```" then
          let lines = String.split_on_char '\n' s in
          let lines = List.tl lines in
          let lines =
            match List.rev lines with
            | last :: rest
              when String.length last >= 3 && String.sub last 0 3 = "```" ->
                List.rev rest
            | _ -> lines
          in
          String.concat "\n" lines
        else s
      in
      match parse_steps plan_text with
      | Error e ->
          let elapsed_s = Unix.gettimeofday () -. start_time in
          Lwt.return
            {
              steps_executed = [];
              error = Some ("Plan parsing failed: " ^ e);
              extracted_data = None;
              final_url = page_state;
              elapsed_s;
            }
      | Ok steps ->
          (* Execute each step *)
          let rec exec_steps acc = function
            | [] -> Lwt.return (List.rev acc, None)
            | step :: rest -> (
                let* result = execute_step browser step in
                match result with
                | Ok s -> exec_steps ((step, s) :: acc) rest
                | Error e ->
                    Lwt.return (List.rev ((step, "Error: " ^ e) :: acc), Some e)
                )
          in
          let* steps_executed, error = exec_steps [] steps in
          let* final_url_r =
            Cdp_client.evaluate browser ~expression:"location.href" ()
          in
          let final_url =
            match final_url_r with Ok s -> s | Error _ -> page_state
          in
          let extracted_data =
            (* Check if last successful step was a content extraction *)
            match List.rev steps_executed with
            | (step, content) :: _ when step.action = "content" -> Some content
            | _ -> None
          in
          let elapsed_s = Unix.gettimeofday () -. start_time in
          Lwt.return
            { steps_executed; error; extracted_data; final_url; elapsed_s })
    (fun exn ->
      let elapsed_s = Unix.gettimeofday () -. start_time in
      Lwt.return
        {
          steps_executed = [];
          error = Some ("LLM call failed: " ^ Printexc.to_string exn);
          extracted_data = None;
          final_url = page_state;
          elapsed_s;
        })

let format_result (r : browse_result) =
  let buf = Buffer.create 256 in
  if r.steps_executed <> [] then begin
    Buffer.add_string buf "Steps executed:\n";
    List.iteri
      (fun i (step, result) ->
        Buffer.add_string buf
          (Printf.sprintf "  %d. %s: %s\n" (i + 1) step.description
             (if String.length result > 200 then String.sub result 0 200 ^ "..."
              else result)))
      r.steps_executed
  end;
  (match r.error with
  | Some e -> Buffer.add_string buf (Printf.sprintf "\nError: %s\n" e)
  | None -> ());
  (match r.extracted_data with
  | Some d -> Buffer.add_string buf (Printf.sprintf "\nExtracted data:\n%s\n" d)
  | None -> ());
  Buffer.add_string buf (Printf.sprintf "\nFinal URL: %s\n" r.final_url);
  Buffer.add_string buf (Printf.sprintf "Elapsed: %.1fs\n" r.elapsed_s);
  Buffer.contents buf
