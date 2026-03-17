(** Discord Gateway Protocol — Formal Verification

    Spec-only Coq formalization of the Discord gateway state machine
    from src/discord_gateway.ml. Models the opcode-driven protocol:
    Hello, Identify, Resume, Heartbeat, Dispatch, Reconnect,
    Invalid Session. Proves safety invariants about heartbeat handling,
    session lifecycle, and reconnection logic.

    No extraction needed.
*)

Require Import Coq.Bool.Bool.
Require Import Coq.Arith.Arith.
Require Import Coq.Arith.PeanoNat.
Require Import Lia.

Module DiscordGateway.

(** * Types *)

(** Gateway opcodes (matching Discord API) *)
Inductive opcode : Type :=
  | Dispatch          (* 0: server -> client *)
  | Heartbeat         (* 1: bidirectional *)
  | Identify          (* 2: client -> server *)
  | Resume            (* 6: client -> server *)
  | Reconnect         (* 7: server -> client *)
  | InvalidSession    (* 9: server -> client *)
  | Hello             (* 10: server -> client *)
  | HeartbeatAck.     (* 11: server -> client *)

(** Connection phase *)
Inductive conn_phase : Type :=
  | Disconnected
  | AwaitingHello
  | AwaitingReady     (* after Identify/Resume, before READY/RESUMED *)
  | Connected.        (* fully connected, dispatching events *)

(** Gateway state *)
Record gw_state : Type := mk_gw_state {
  phase : conn_phase;
  has_session : bool;     (* session_id is Some *)
  has_seq : bool;         (* seq is Some *)
  hb_ack_received : bool; (* heartbeat ACK flag *)
  hb_running : bool;      (* heartbeat loop active *)
}.

(** * Initial state *)

Definition initial_state : gw_state :=
  mk_gw_state Disconnected false false false false.

(** * State transitions *)

(** Client actions in response to server opcodes *)

(** Hello (op 10): Start heartbeat, then Identify or Resume *)
Definition handle_hello (s : gw_state) : gw_state :=
  mk_gw_state AwaitingReady (has_session s) (has_seq s) true true.

(** HeartbeatAck (op 11): Mark ACK received *)
Definition handle_heartbeat_ack (s : gw_state) : gw_state :=
  mk_gw_state (phase s) (has_session s) (has_seq s) true (hb_running s).

(** Dispatch (op 0) with READY: Store session_id, update seq *)
Definition handle_ready (s : gw_state) : gw_state :=
  mk_gw_state Connected true true (hb_ack_received s) (hb_running s).

(** Dispatch (op 0) with RESUMED: Back to connected *)
Definition handle_resumed (s : gw_state) : gw_state :=
  mk_gw_state Connected (has_session s) (has_seq s)
    (hb_ack_received s) (hb_running s).

(** Dispatch (op 0) with other event: Update seq only *)
Definition handle_dispatch (s : gw_state) : gw_state :=
  mk_gw_state (phase s) (has_session s) true
    (hb_ack_received s) (hb_running s).

(** Reconnect (op 7): Close connection, will reconnect *)
Definition handle_reconnect (s : gw_state) : gw_state :=
  mk_gw_state Disconnected (has_session s) (has_seq s) false false.

(** Invalid Session (op 9, resumable=true): Wait then Resume *)
Definition handle_invalid_session_resumable (s : gw_state) : gw_state :=
  mk_gw_state AwaitingReady (has_session s) (has_seq s)
    (hb_ack_received s) (hb_running s).

(** Invalid Session (op 9, resumable=false): Clear session, re-Identify *)
Definition handle_invalid_session_fresh (s : gw_state) : gw_state :=
  mk_gw_state AwaitingReady false false
    (hb_ack_received s) (hb_running s).

(** Heartbeat timeout (no ACK): Zombie, close connection *)
Definition handle_heartbeat_timeout (s : gw_state) : gw_state :=
  mk_gw_state Disconnected (has_session s) (has_seq s) false false.

(** WebSocket close: Disconnected *)
Definition handle_ws_close (s : gw_state) : gw_state :=
  mk_gw_state Disconnected (has_session s) (has_seq s) false false.

(** WebSocket open: Awaiting Hello *)
Definition handle_ws_open (s : gw_state) : gw_state :=
  mk_gw_state AwaitingHello (has_session s) (has_seq s) false false.

(** * Predicates *)

Definition can_resume (s : gw_state) : bool :=
  has_session s.

Definition is_connected (s : gw_state) : bool :=
  match phase s with
  | Connected => true
  | _ => false
  end.

Definition is_disconnected (s : gw_state) : bool :=
  match phase s with
  | Disconnected => true
  | _ => false
  end.

(** * Invariant Theorems *)

(** Theorem 1: Initial state is disconnected with no session. *)
Theorem initial_is_disconnected :
  is_disconnected initial_state = true /\
  has_session initial_state = false /\
  hb_running initial_state = false.
Proof.
  repeat split; reflexivity.
Qed.

(** Theorem 2: Hello always starts heartbeat. *)
Theorem hello_starts_heartbeat :
  forall s, hb_running (handle_hello s) = true.
Proof.
  intros s. reflexivity.
Qed.

(** Theorem 3: Hello sets ACK flag (initial jitter ACK). *)
Theorem hello_sets_ack :
  forall s, hb_ack_received (handle_hello s) = true.
Proof.
  intros s. reflexivity.
Qed.

(** Theorem 4: HeartbeatAck sets the ACK flag. *)
Theorem heartbeat_ack_sets_flag :
  forall s, hb_ack_received (handle_heartbeat_ack s) = true.
Proof.
  intros s. reflexivity.
Qed.

(** Theorem 5: READY event establishes session. *)
Theorem ready_establishes_session :
  forall s,
    has_session (handle_ready s) = true /\
    has_seq (handle_ready s) = true /\
    is_connected (handle_ready s) = true.
Proof.
  intros s. repeat split; reflexivity.
Qed.

(** Theorem 6: Reconnect preserves session for resumption. *)
Theorem reconnect_preserves_session :
  forall s,
    has_session (handle_reconnect s) = has_session s /\
    has_seq (handle_reconnect s) = has_seq s.
Proof.
  intros s. split; reflexivity.
Qed.

(** Theorem 7: Reconnect disconnects and stops heartbeat. *)
Theorem reconnect_disconnects :
  forall s,
    is_disconnected (handle_reconnect s) = true /\
    hb_running (handle_reconnect s) = false.
Proof.
  intros s. split; reflexivity.
Qed.

(** Theorem 8: Invalid session (fresh) clears session state. *)
Theorem invalid_session_fresh_clears :
  forall s,
    has_session (handle_invalid_session_fresh s) = false /\
    has_seq (handle_invalid_session_fresh s) = false.
Proof.
  intros s. split; reflexivity.
Qed.

(** Theorem 9: Invalid session (resumable) preserves session. *)
Theorem invalid_session_resumable_preserves :
  forall s,
    has_session (handle_invalid_session_resumable s) = has_session s /\
    has_seq (handle_invalid_session_resumable s) = has_seq s.
Proof.
  intros s. split; reflexivity.
Qed.

(** Theorem 10: Heartbeat timeout disconnects. *)
Theorem heartbeat_timeout_disconnects :
  forall s,
    is_disconnected (handle_heartbeat_timeout s) = true /\
    hb_running (handle_heartbeat_timeout s) = false.
Proof.
  intros s. split; reflexivity.
Qed.

(** Theorem 11: After READY, can_resume is true. *)
Theorem ready_enables_resume :
  forall s, can_resume (handle_ready s) = true.
Proof.
  intros s. reflexivity.
Qed.

(** Theorem 12: After invalid_session_fresh, can_resume is false. *)
Theorem fresh_disables_resume :
  forall s, can_resume (handle_invalid_session_fresh s) = false.
Proof.
  intros s. reflexivity.
Qed.

(** Theorem 13: Dispatch updates seq. *)
Theorem dispatch_updates_seq :
  forall s, has_seq (handle_dispatch s) = true.
Proof.
  intros s. reflexivity.
Qed.

(** Theorem 14: ws_close preserves session for reconnect. *)
Theorem ws_close_preserves_session :
  forall s,
    has_session (handle_ws_close s) = has_session s /\
    has_seq (handle_ws_close s) = has_seq s /\
    is_disconnected (handle_ws_close s) = true.
Proof.
  intros s. repeat split; reflexivity.
Qed.

(** Theorem 15: ws_open transitions to AwaitingHello. *)
Theorem ws_open_awaits_hello :
  forall s,
    phase (handle_ws_open s) = AwaitingHello.
Proof.
  intros s. reflexivity.
Qed.

(** Theorem 16: Lifecycle: Disconnected -> ws_open -> Hello -> READY
    produces a connected state with session. *)
Theorem full_connect_lifecycle :
  forall s,
    is_disconnected s = true ->
    let s1 := handle_ws_open s in
    let s2 := handle_hello s1 in
    let s3 := handle_ready s2 in
    is_connected s3 = true /\
    has_session s3 = true /\
    hb_running s3 = true.
Proof.
  intros s Hdisc.
  repeat split; reflexivity.
Qed.

(** Theorem 17: Reconnect lifecycle preserves session for resume. *)
Theorem reconnect_resume_lifecycle :
  forall s,
    has_session s = true ->
    let s1 := handle_reconnect s in
    let s2 := handle_ws_open s1 in
    let s3 := handle_hello s2 in
    can_resume s3 = true /\
    hb_running s3 = true.
Proof.
  intros s Hsess.
  simpl. rewrite Hsess.
  split; reflexivity.
Qed.

(** Theorem 18: Phase classification is exhaustive. *)
Theorem phase_exhaustive :
  forall p,
    p = Disconnected \/ p = AwaitingHello \/
    p = AwaitingReady \/ p = Connected.
Proof.
  intros p. destruct p; auto.
Qed.

(** Theorem 19: Opcode classification is exhaustive. *)
Theorem opcode_exhaustive :
  forall op,
    op = Dispatch \/ op = Heartbeat \/ op = Identify \/
    op = Resume \/ op = Reconnect \/ op = InvalidSession \/
    op = Hello \/ op = HeartbeatAck.
Proof.
  intros op. destruct op;
    first [ left; reflexivity
          | right; left; reflexivity
          | right; right; left; reflexivity
          | right; right; right; left; reflexivity
          | right; right; right; right; left; reflexivity
          | right; right; right; right; right; left; reflexivity
          | right; right; right; right; right; right; left; reflexivity
          | right; right; right; right; right; right; right; reflexivity ].
Qed.

(** Theorem 20: Heartbeat timeout after no ACK is safe to disconnect. *)
Theorem zombie_detection_safe :
  forall s,
    hb_ack_received s = false ->
    is_disconnected (handle_heartbeat_timeout s) = true.
Proof.
  intros s _. reflexivity.
Qed.

End DiscordGateway.
