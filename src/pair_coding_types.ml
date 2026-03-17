(* Pure types and state machine for pair coding sessions.
   FV-compatible: no Lwt, no Sqlite3, no mutable state, no exceptions.
   Uses int for timestamps (ms since epoch) for Coq extraction compatibility. *)

type role = Coordinator | Coder | Observer
type phase = Coding | Review | Iteration | Completion | Done
type interrupt_mode = Asap | Urgent_only | Queued
type note_severity = Critical | High | Medium | Low

type note_category =
  | Bug
  | Style
  | Architecture
  | Optimization
  | Question
  | Suggestion
  | Security
  | Other

type note = {
  id : int;
  description : string;
  category : note_category option;
  severity : note_severity;
  file : string option;
  line : int option;
  resolved : bool;
  created_at_ms : int;
}

type approval = { approved : bool; comment : string; timestamp_ms : int }

type transition =
  | Start_review
  | Start_iteration
  | Complete
  | Finalize
  | Timeout
  | Abort

type state = {
  phase : phase;
  review_round : int;
  max_review_rounds : int;
  notes : note list;
  coder_approval : approval option;
  observer_approval : approval option;
  interrupts : int;
}

let role_to_string = function
  | Coordinator -> "coordinator"
  | Coder -> "coder"
  | Observer -> "observer"

let role_of_string = function
  | "coordinator" | "coord" -> Some Coordinator
  | "coder" -> Some Coder
  | "observer" | "obsrv" -> Some Observer
  | _ -> None

let role_key_suffix = function
  | Coordinator -> "coord"
  | Coder -> "coder"
  | Observer -> "obsrv"

let phase_to_string = function
  | Coding -> "coding"
  | Review -> "review"
  | Iteration -> "iteration"
  | Completion -> "completion"
  | Done -> "done"

let phase_of_string = function
  | "coding" -> Some Coding
  | "review" -> Some Review
  | "iteration" -> Some Iteration
  | "completion" -> Some Completion
  | "done" -> Some Done
  | _ -> None

let interrupt_mode_to_string = function
  | Asap -> "asap"
  | Urgent_only -> "urgent_only"
  | Queued -> "queued"

let interrupt_mode_of_string = function
  | "asap" -> Some Asap
  | "urgent_only" -> Some Urgent_only
  | "queued" -> Some Queued
  | _ -> None

let severity_to_string = function
  | Critical -> "critical"
  | High -> "high"
  | Medium -> "medium"
  | Low -> "low"

let severity_of_string = function
  | "critical" -> Some Critical
  | "high" -> Some High
  | "medium" -> Some Medium
  | "low" -> Some Low
  | _ -> None

let category_to_string = function
  | Bug -> "bug"
  | Style -> "style"
  | Architecture -> "architecture"
  | Optimization -> "optimization"
  | Question -> "question"
  | Suggestion -> "suggestion"
  | Security -> "security"
  | Other -> "other"

let category_of_string = function
  | "bug" -> Some Bug
  | "style" -> Some Style
  | "architecture" -> Some Architecture
  | "optimization" -> Some Optimization
  | "question" -> Some Question
  | "suggestion" -> Some Suggestion
  | "security" -> Some Security
  | "other" -> Some Other
  | _ -> None

let transition_to_string = function
  | Start_review -> "start_review"
  | Start_iteration -> "start_iteration"
  | Complete -> "complete"
  | Finalize -> "finalize"
  | Timeout -> "timeout"
  | Abort -> "abort"

let transition_of_string = function
  | "start_review" -> Some Start_review
  | "start_iteration" -> Some Start_iteration
  | "complete" -> Some Complete
  | "finalize" -> Some Finalize
  | "timeout" -> Some Timeout
  | "abort" -> Some Abort
  | _ -> None

let initial_state ~max_review_rounds =
  {
    phase = Coding;
    review_round = 0;
    max_review_rounds;
    notes = [];
    coder_approval = None;
    observer_approval = None;
    interrupts = 0;
  }

let both_approved state =
  match (state.coder_approval, state.observer_approval) with
  | Some { approved = true; _ }, Some { approved = true; _ } -> true
  | _ -> false

let has_blocking_notes state =
  List.exists
    (fun (n : note) ->
      (not n.resolved) && (n.severity = Critical || n.severity = High))
    state.notes

let transition state tr =
  match (state.phase, tr) with
  | Coding, Start_review ->
      Ok
        {
          state with
          phase = Review;
          review_round = state.review_round + 1;
          coder_approval = None;
          observer_approval = None;
        }
  | Review, Start_iteration -> Ok { state with phase = Iteration }
  | Iteration, Start_review ->
      Ok
        {
          state with
          phase = Review;
          review_round = state.review_round + 1;
          coder_approval = None;
          observer_approval = None;
        }
  | Review, Complete ->
      if both_approved state || state.review_round >= state.max_review_rounds
      then Ok { state with phase = Completion }
      else
        Error
          "Cannot complete: both agents must approve, or max review rounds \
           must be reached."
  | Completion, Finalize -> Ok { state with phase = Done }
  | _, Timeout -> Ok { state with phase = Done }
  | _, Abort -> Ok { state with phase = Done }
  | Done, _ -> Error "Session is already done. No further transitions allowed."
  | phase, tr ->
      Error
        (Printf.sprintf "Invalid transition %s from phase %s."
           (transition_to_string tr) (phase_to_string phase))
