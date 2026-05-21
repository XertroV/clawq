(** Live-test a target model before committing a model switch.

    The goal is to catch unreachable/misconfigured models *before* persisting
    the change, so a bad selection can never brick a session. Both preflight
    checks (provider exists, has auth) and a minimal live completion are run.

    See B600. *)

let default_timeout_s = 30.0

type result = Ok_validated | Error_msg of string

let make_test_config ~(config : Runtime_config.t) ~model : Runtime_config.t =
  {
    config with
    agent_defaults = { config.agent_defaults with primary_model = model };
  }

(* Best-effort preflight: detect obvious misconfiguration without making a
   network call. Returns Some error_msg if we should skip the live test. *)
let preflight ~(config : Runtime_config.t) ~model : string option =
  let provider, _model_id, fmt = Models_catalog.split_name model in
  match fmt with
  | Models_catalog.Plain -> None
  | Models_catalog.Canonical | Models_catalog.Legacy -> (
      match List.assoc_opt provider config.providers with
      | None ->
          Some
            (Printf.sprintf
               "provider '%s' is not configured in config.json. Run 'clawq \
                config provider add %s ...' or pick a model from a configured \
                provider ('clawq models list')."
               provider provider)
      | Some pc ->
          if Provider.provider_has_routable_auth ~name:provider pc then None
          else
            Some
              (Printf.sprintf
                 "provider '%s' has no routable auth (api_key missing or OAuth \
                  credentials expired). Run 'clawq config provider set %s \
                  api_key=...' or re-auth the provider."
                 provider provider))

let test_completion ~(config : Runtime_config.t) ~model ~timeout_s :
    result Lwt.t =
  let open Lwt.Syntax in
  let test_config = make_test_config ~config ~model in
  let test_messages =
    [
      Provider.make_message ~role:"user"
        ~content:"Respond with the single word OK.";
    ]
  in
  Lwt.catch
    (fun () ->
      let* _resp =
        Lwt_unix.with_timeout timeout_s (fun () ->
            Provider.complete ~config:test_config ~messages:test_messages ())
      in
      Lwt.return Ok_validated)
    (function
      | Lwt_unix.Timeout ->
          Lwt.return
            (Error_msg
               (Printf.sprintf
                  "validation timed out after %.0fs — model did not respond. \
                   Check provider base_url, network, or pick a different \
                   model."
                  timeout_s))
      | Failure msg -> Lwt.return (Error_msg msg)
      | exn -> Lwt.return (Error_msg (Printexc.to_string exn)))

let validate ~(config : Runtime_config.t) ~model
    ?(timeout_s = default_timeout_s) () : result Lwt.t =
  match preflight ~config ~model with
  | Some err -> Lwt.return (Error_msg err)
  | None -> test_completion ~config ~model ~timeout_s

let validate_sync ~config ~model ?(timeout_s = default_timeout_s) () : result =
  Lwt_main.run (validate ~config ~model ~timeout_s ())

(** Format a result as a user-facing string. [previous_label] describes the
    current/previous model for rollback hints. [rollback_cmd] is the literal
    shell command to run to undo the switch. *)
let format_failure ~rollback_cmd msg =
  Printf.sprintf
    "Error: model validation failed — %s\n\
     Previous model remains active. To re-attempt or rollback explicitly:\n\
    \  %s"
    msg rollback_cmd
