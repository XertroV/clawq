(** F10: Agent Termination and History Bounds

    This module proves:
    - The agent turn loop terminates in at most max_tool_iterations steps
    - History length is bounded after trim_history
    - trim_history is idempotent

    Spec-only module (no extraction - loop calls Lwt/LLM).
*)

Require Import Coq.Lists.List.
Require Import Coq.Arith.Arith.
Require Import Coq.Arith.PeanoNat.
Require Import Coq.Bool.Bool.
Require Import Coq.Strings.String.
Require Import Lia.
Import ListNotations.

(** Avoid string scope conflicts for list/nat operations *)
Local Open Scope list_scope.
Local Open Scope nat_scope.

Module AgentLoop.

(** * Abstract Types *)

(** Message in conversation history (newest-first, matching src/agent.ml). *)
Inductive message : Type :=
  | UserMsg : string -> message
  | AssistantMsg : string -> message
  | AssistantToolCallMsg : list string -> message
  | ToolResultMsg : string -> string -> message.

(** LLM response: either text or tool calls *)
Inductive response : Type :=
  | TextResponse : string -> response
  | ToolCalls : list string -> response.

(** Agent configuration *)
Record config : Type := {
  max_tool_iterations : nat;
  effective_max_messages : nat;
}.

(** * History Operations *)

Definition history := list message.

(** trim_history keeps the newest-first prefix when history exceeds max,
    matching `Agent.trim_history` in `src/agent.ml`. *)
Definition trim_history (max : nat) (h : history) : history :=
  if Nat.ltb (List.length h) max then h
  else firstn max h.

(** Emergency force-compression also keeps a newest-first prefix, matching
    `Agent.force_compress_history` after per-message truncation is abstracted
    away. *)
Definition force_compress_history (keep_recent : nat) (h : history) : history :=
  firstn keep_recent h.

(** Runtime-aligned tool cycle shape used in src/agent.ml. *)
Definition append_tool_cycle (calls : list string) (h : history) : history :=
  let h1 := AssistantToolCallMsg calls :: h in
  fold_left
    (fun acc name => ToolResultMsg name "result" :: acc)
    calls h1.

Lemma fold_left_tool_results_extends_acc :
  forall calls acc,
    exists prefix,
      fold_left
        (fun acc name => ToolResultMsg name "result" :: acc)
        calls acc = prefix ++ acc.
Proof.
  induction calls as [|c cs IH]; intro acc.
  - exists [].
    reflexivity.
  - simpl.
    destruct (IH (ToolResultMsg c "result" :: acc)) as [prefix Hprefix].
    exists (prefix ++ [ToolResultMsg c "result"]).
    rewrite Hprefix.
    rewrite <- app_assoc.
    reflexivity.
Qed.

Lemma append_tool_cycle_extends_history :
  forall calls h,
    exists prefix, append_tool_cycle calls h = prefix ++ h.
Proof.
  intros calls h.
  unfold append_tool_cycle.
  destruct
    (fold_left_tool_results_extends_acc calls (AssistantToolCallMsg calls :: h))
    as [prefix Hprefix].
  exists (prefix ++ [AssistantToolCallMsg calls]).
  rewrite Hprefix.
  rewrite <- app_assoc.
  reflexivity.
Qed.

(** * Trim History Properties *)

Lemma trim_history_length :
  forall max h,
    List.length (trim_history max h) <= max.
Proof.
  intros max h.
  unfold trim_history.
  destruct (Nat.ltb (List.length h) max) eqn:Hlen.
  - apply Nat.ltb_lt in Hlen.
    lia.
  - apply Nat.ltb_ge in Hlen.
    rewrite firstn_length_le by lia.
    lia.
Qed.

Lemma trim_history_idempotent :
  forall max h,
    trim_history max (trim_history max h) = trim_history max h.
Proof.
  intros max h.
  unfold trim_history.
  destruct (Nat.ltb (List.length h) max) eqn:Hlen.
  - (* Case: List.length h < max, trim returns h unchanged *)
    rewrite Hlen.
    reflexivity.
  - (* Case: List.length h >= max, trim returns firstn max h *)
    apply Nat.ltb_ge in Hlen.
    (* Key: List.length (firstn max h) <= max always *)
    destruct (Nat.ltb (List.length (firstn max h)) max) eqn:Htrim.
    + (* List.length (firstn max h) < max: trim returns firstn max h *)
      reflexivity.
    + (* List.length (firstn max h) >= max, i.e., = max *)
      (* firstn max (firstn max h) = firstn (min max max) h = firstn max h *)
      rewrite firstn_firstn.
      rewrite Nat.min_id.
      reflexivity.
Qed.

Lemma trim_history_preserves_prefix :
  forall max h,
    exists prefix_suffix, trim_history max h ++ prefix_suffix = h.
Proof.
  intros max h.
  unfold trim_history.
  destruct (Nat.ltb (List.length h) max) eqn:Hlen.
  - (* Case: List.length h < max, trim returns h unchanged *)
    exists [].
    rewrite app_nil_r.
    reflexivity.
  - (* Case: List.length h >= max, trim returns firstn max h *)
    apply Nat.ltb_ge in Hlen.
    exists (skipn max h).
    rewrite firstn_skipn.
    reflexivity.
Qed.

Lemma force_compress_history_preserves_prefix :
  forall keep_recent h,
    exists prefix_suffix,
      force_compress_history keep_recent h ++ prefix_suffix = h.
Proof.
  intros keep_recent h.
  unfold force_compress_history.
  exists (skipn keep_recent h).
  rewrite firstn_skipn.
  reflexivity.
Qed.

(** * Agent Loop Model *)

(** Abstract step result: either continue or halt *)
Inductive step_result : Type :=
  | Continue : response -> step_result
  | Halt : response -> step_result.

(** Abstract decision: should we continue after a tool call? *)
Parameter should_continue : response -> nat -> config -> bool.

(** The agent loop, modeled with fuel (iteration count) *)
Fixpoint loop (fuel : nat) (cfg : config) (h : history) : response :=
  match fuel with
  | 0 => TextResponse "max iterations reached"
  | S fuel' =>
      let r := (* abstract LLM call *) TextResponse "" in
      if should_continue r fuel cfg then
        loop fuel' cfg h
      else
        r
  end.

Definition run_turn (cfg : config) (h : history) : response :=
  loop cfg.(max_tool_iterations) cfg h.

Fixpoint loop_steps (fuel : nat) (cfg : config) (h : history) : nat :=
  match fuel with
  | 0 => 0
  | S fuel' =>
      let r := TextResponse "" in
      if should_continue r fuel cfg then S (loop_steps fuel' cfg h) else 1
  end.

Theorem loop_steps_bounded_by_fuel :
  forall fuel cfg h,
    loop_steps fuel cfg h <= fuel.
Proof.
  induction fuel as [|fuel' IH]; intros cfg h.
  - simpl. lia.
  - simpl.
    specialize (IH cfg h).
    destruct (should_continue (TextResponse "") (S fuel') cfg).
    + simpl. lia.
    + lia.
Qed.

Theorem run_turn_global_iteration_bound :
  forall cfg h,
    loop_steps cfg.(max_tool_iterations) cfg h <= cfg.(max_tool_iterations).
Proof.
  intros cfg h.
  apply loop_steps_bounded_by_fuel.
Qed.

(** * Termination Proof *)

Theorem loop_terminates :
  forall fuel cfg h,
    exists resp, loop fuel cfg h = resp.
Proof.
  intros fuel cfg h.
  induction fuel.
  - exists (TextResponse "max iterations reached").
    reflexivity.
  - destruct (should_continue (TextResponse "") (S fuel) cfg) eqn:Hcont.
    + destruct IHfuel as [resp IH].
      exists resp.
      simpl.
      rewrite Hcont.
      assumption.
    + exists (TextResponse "").
      simpl.
      rewrite Hcont.
      reflexivity.
Qed.

Lemma loop_zero_halts :
  forall cfg h,
    loop 0 cfg h = TextResponse "max iterations reached".
Proof.
  intros cfg h.
  reflexivity.
Qed.

(** * History Bounding After Turn *)

(** After a turn completes, history is bounded *)
Definition history_bounded (max : nat) (h : history) : Prop :=
  List.length h <= max.

Theorem trim_history_establishes_bound :
  forall max h,
    history_bounded max (trim_history max h).
Proof.
  intros max h.
  unfold history_bounded.
  apply trim_history_length.
Qed.

(** * Config Invariants *)

(** Valid configuration has positive limits *)
Definition valid_config (cfg : config) : Prop :=
  cfg.(max_tool_iterations) > 0 /\
  cfg.(effective_max_messages) > 0.

(** History bound matches config *)
Corollary config_preserves_history_bound :
  forall cfg h,
    valid_config cfg ->
    history_bounded cfg.(effective_max_messages) (trim_history cfg.(effective_max_messages) h).
Proof.
  intros cfg h [Hiter Hmax].
  apply trim_history_establishes_bound.
Qed.

(** * Summary: Key Properties *)

(** The agent loop model satisfies:
    1. Global iteration bound (`run_turn_global_iteration_bound`)
    2. Termination (`loop_terminates`)
    3. Tool-call/tool-result history shape (`append_tool_cycle_extends_history`)
    4. Newest-first ordering preservation under trimming/compaction
       (`trim_history_preserves_prefix`,
        `force_compress_history_preserves_prefix`,
        `trim_history_idempotent`)
 *)

End AgentLoop.
