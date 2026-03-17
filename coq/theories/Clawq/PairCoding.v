(** B533: Pair Coding State Machine Formal Verification

    Spec-only Coq formalization of the pair coding session state machine
    from src/pair_coding_types.ml. Proves 8 safety invariants and 4 helper
    lemmas about the phase transition protocol. No extraction needed.

    Critical semantic detail: The OCaml transition function's match ordering
    has (_, Timeout) and (_, Abort) wildcards BEFORE (Done, _). This means
    Timeout/Abort succeed even from Done (returning Done). The Coq model
    replicates this ordering exactly.
*)

Require Import Coq.Bool.Bool.
Require Import Coq.Arith.Arith.
Require Import Coq.Arith.PeanoNat.
Require Import Coq.Lists.List.
Require Import Lia.
Import ListNotations.

Module PairCoding.

(** * Section 1: Types *)

Inductive role : Type :=
  | Coordinator
  | Coder
  | Observer.

Inductive phase : Type :=
  | Coding
  | Review
  | Iteration
  | Completion
  | Done.

Inductive note_severity : Type :=
  | Critical
  | High
  | Medium
  | Low.

Record note : Type := mk_note {
  note_severity_field : note_severity;
  note_resolved : bool;
}.

Record approval : Type := mk_approval {
  approved : bool;
}.

Inductive transition : Type :=
  | Start_review
  | Start_iteration
  | Complete
  | Finalize
  | Timeout
  | Abort.

Record state : Type := mk_state {
  st_phase : phase;
  review_round : nat;
  max_review_rounds : nat;
  notes : list note;
  coder_approval : option approval;
  observer_approval : option approval;
}.

(** * Section 2: Helpers *)

Definition phase_level (p : phase) : nat :=
  match p with
  | Coding => 0
  | Review => 1
  | Iteration => 1
  | Completion => 2
  | Done => 3
  end.

Definition initial_state (max_rounds : nat) : state :=
  mk_state Coding 0 max_rounds [] None None.

Definition both_approved (s : state) : bool :=
  match coder_approval s, observer_approval s with
  | Some ca, Some oa => andb (approved ca) (approved oa)
  | _, _ => false
  end.

Definition is_blocking (n : note) : bool :=
  andb (negb (note_resolved n))
       (match note_severity_field n with
        | Critical => true
        | High => true
        | _ => false
        end).

Definition has_blocking_notes (s : state) : bool :=
  existsb is_blocking (notes s).

(** * Section 3: Core Transition Function *)

(** Match arms ordered to replicate OCaml semantics exactly.
    In particular, Timeout and Abort are matched BEFORE Done,
    so they succeed (returning Done) even from Done state.
    Uses option state instead of state + string since this is
    spec-only (error messages are not needed for proofs). *)

Definition do_transition (s : state) (tr : transition)
    : option state :=
  match st_phase s, tr with
  | Coding, Start_review =>
      Some (mk_state Review (S (review_round s)) (max_review_rounds s)
                     (notes s) None None)
  | Review, Start_iteration =>
      Some (mk_state Iteration (review_round s) (max_review_rounds s)
                     (notes s) (coder_approval s) (observer_approval s))
  | Iteration, Start_review =>
      Some (mk_state Review (S (review_round s)) (max_review_rounds s)
                     (notes s) None None)
  | Review, Complete =>
      if orb (both_approved s) (max_review_rounds s <=? review_round s)
      then Some (mk_state Completion (review_round s) (max_review_rounds s)
                           (notes s) (coder_approval s) (observer_approval s))
      else None
  | Completion, Finalize =>
      Some (mk_state Done (review_round s) (max_review_rounds s)
                     (notes s) (coder_approval s) (observer_approval s))
  (* Timeout and Abort match ANY phase, including Done *)
  | _, Timeout =>
      Some (mk_state Done (review_round s) (max_review_rounds s)
                     (notes s) (coder_approval s) (observer_approval s))
  | _, Abort =>
      Some (mk_state Done (review_round s) (max_review_rounds s)
                     (notes s) (coder_approval s) (observer_approval s))
  | Done, _ => None
  | _, _ => None
  end.

(** * Section 4: Reachability *)

Inductive reachable : state -> Prop :=
  | reach_init : forall n, reachable (initial_state n)
  | reach_step : forall s s' tr,
      reachable s ->
      do_transition s tr = Some s' ->
      reachable s'.

(** * Section 5: Invariant Theorems *)

(** Local tactic: destruct the if-condition in H, then solve. *)
Local Ltac solve_if_case H :=
  match type of H with
  | context [if ?c then _ else _] =>
      destruct c; [injection H as H; subst; simpl; lia | discriminate]
  end.

(** Theorem 1: Phase level is monotonically non-decreasing on
    successful transitions. *)
Theorem phase_level_monotone :
  forall s s' tr,
    do_transition s tr = Some s' ->
    phase_level (st_phase s) <= phase_level (st_phase s').
Proof.
  intros [p r mr ns ca oa] s' tr H.
  destruct p, tr;
    cbn [do_transition st_phase review_round max_review_rounds
         notes coder_approval observer_approval] in H;
    try discriminate;
    try (injection H as H; subst; simpl; lia).
  - solve_if_case H.
Qed.

(** Theorem 2: Review round is monotonically non-decreasing. *)
Theorem review_round_monotone :
  forall s s' tr,
    do_transition s tr = Some s' ->
    review_round s <= review_round s'.
Proof.
  intros [p r mr ns ca oa] s' tr H.
  destruct p, tr;
    cbn [do_transition st_phase review_round max_review_rounds
         notes coder_approval observer_approval] in H;
    try discriminate;
    try (injection H as H; subst; simpl; lia).
  - solve_if_case H.
Qed.

(** Theorem 3 (replacement): review_round starts at zero.

    NOTE: The originally planned theorem review_round_bounded
    (review_round <= max_review_rounds for all reachable states) is
    provably FALSE. Counterexample with max_review_rounds=1:
      1. Start_review -> round=1, phase=Review
      2. Start_iteration -> round=1, phase=Iteration
      3. Start_review -> round=2, phase=Review (round > max!)
    Start_review increments unconditionally; no guard checks round
    against max. The bound only applies at Complete (captured by
    theorem 4: completion_requires_approval_or_max_rounds). *)

Theorem review_round_starts_zero :
  forall n, review_round (initial_state n) = 0.
Proof.
  intros n. reflexivity.
Qed.

Theorem start_review_increments_round :
  forall s s',
    do_transition s Start_review = Some s' ->
    review_round s' = S (review_round s).
Proof.
  intros [p r mr ns ca oa] s' H.
  destruct p;
    cbn [do_transition st_phase review_round max_review_rounds
         notes coder_approval observer_approval] in H;
    try discriminate;
    injection H as H; subst; simpl; reflexivity.
Qed.

(** Theorem 4: Completion requires either both-approved or max rounds
    reached. *)
Theorem completion_requires_approval_or_max_rounds :
  forall s s',
    do_transition s Complete = Some s' ->
    both_approved s = true \/ max_review_rounds s <= review_round s.
Proof.
  intros [p r mr ns ca oa] s' H.
  destruct p;
    cbn [do_transition st_phase review_round max_review_rounds
         notes coder_approval observer_approval] in H;
    try discriminate.
  - (* Review *)
    match type of H with
    | context [if ?c then _ else _] =>
        destruct c eqn:Hcond; [| discriminate]
    end.
    apply orb_true_iff in Hcond.
    destruct Hcond as [Happr | Hle].
    + left. exact Happr.
    + right. apply Nat.leb_le. exact Hle.
Qed.

(** Theorem 5: Done is terminal — no transition from Done changes
    the phase. Timeout/Abort from Done return Done (same phase). *)
Theorem done_is_terminal :
  forall s tr s',
    st_phase s = Done ->
    do_transition s tr = Some s' ->
    st_phase s' = Done.
Proof.
  intros [p r mr ns ca oa] tr s' Hdone H.
  simpl in Hdone. subst p.
  destruct tr;
    cbn [do_transition st_phase review_round max_review_rounds
         notes coder_approval observer_approval] in H;
    try discriminate;
    injection H as H; subst; simpl; reflexivity.
Qed.

(** Theorem 6: Entering Review clears both approvals. *)
Theorem review_entry_clears_approvals :
  forall s s',
    do_transition s Start_review = Some s' ->
    coder_approval s' = None /\ observer_approval s' = None.
Proof.
  intros [p r mr ns ca oa] s' H.
  destruct p;
    cbn [do_transition st_phase review_round max_review_rounds
         notes coder_approval observer_approval] in H;
    try discriminate;
    injection H as H; subst; simpl; auto.
Qed.

(** Theorem 7: both_approved is decidable. *)
Theorem both_approved_decidable :
  forall s, both_approved s = true \/ both_approved s = false.
Proof.
  intros s.
  destruct (both_approved s); auto.
Qed.

(** Theorem 8: has_blocking_notes is decidable. *)
Theorem has_blocking_notes_decidable :
  forall s, has_blocking_notes s = true \/ has_blocking_notes s = false.
Proof.
  intros s.
  destruct (has_blocking_notes s); auto.
Qed.

(** * Section 6: Helper Lemmas *)

(** do_transition is deterministic (it is a pure function). *)
Lemma transition_deterministic :
  forall s tr r1 r2,
    do_transition s tr = r1 ->
    do_transition s tr = r2 ->
    r1 = r2.
Proof.
  intros s tr r1 r2 H1 H2.
  rewrite <- H1. exact H2.
Qed.

(** The initial state has phase Coding. *)
Lemma initial_state_is_coding :
  forall n, st_phase (initial_state n) = Coding.
Proof.
  intros n. reflexivity.
Qed.

(** Abort always succeeds from any phase (including Done). *)
Lemma abort_always_succeeds :
  forall s, exists s', do_transition s Abort = Some s'.
Proof.
  intros [p r mr ns ca oa].
  destruct p; eexists; simpl; reflexivity.
Qed.

(** Timeout always succeeds from any phase (including Done). *)
Lemma timeout_always_succeeds :
  forall s, exists s', do_transition s Timeout = Some s'.
Proof.
  intros [p r mr ns ca oa].
  destruct p; eexists; simpl; reflexivity.
Qed.

(** * Section 7: Extended Properties *)

(** Common tactic for transition proofs that destruct state and transition. *)
Local Ltac destruct_transition H :=
  let p := fresh "p" in let r := fresh "r" in
  let mr := fresh "mr" in let ns := fresh "ns" in
  let ca := fresh "ca" in let oa := fresh "oa" in
  match type of H with
  | do_transition ?s _ = _ =>
      destruct s as [p r mr ns ca oa];
      destruct p;
      cbn [do_transition st_phase review_round max_review_rounds
           notes coder_approval observer_approval] in H;
      try discriminate
  end.

(** ** 7.1: Timeout and Abort always produce Done *)

Lemma timeout_produces_done :
  forall s s',
    do_transition s Timeout = Some s' ->
    st_phase s' = Done.
Proof.
  intros s s' H. destruct_transition H;
    injection H as H; subst; reflexivity.
Qed.

Lemma abort_produces_done :
  forall s s',
    do_transition s Abort = Some s' ->
    st_phase s' = Done.
Proof.
  intros s s' H. destruct_transition H;
    injection H as H; subst; reflexivity.
Qed.

(** ** 7.2: Liveness — Done is always reachable *)

Theorem done_always_reachable :
  forall s, reachable s ->
    exists s', reachable s' /\ st_phase s' = Done.
Proof.
  intros s Hreach.
  destruct (abort_always_succeeds s) as [s' Htrans].
  exists s'. split.
  - eapply reach_step; eauto.
  - eapply abort_produces_done; eauto.
Qed.

(** ** 7.3: max_review_rounds is invariant across transitions *)

Lemma max_review_rounds_preserved :
  forall s s' tr,
    do_transition s tr = Some s' ->
    max_review_rounds s' = max_review_rounds s.
Proof.
  intros [p r mr ns ca oa] s' tr H.
  destruct p, tr;
    cbn [do_transition st_phase review_round max_review_rounds
         notes coder_approval observer_approval] in H;
    try discriminate;
    try (injection H as H; subst; simpl; reflexivity).
  - (* Review, Complete *)
    match type of H with
    | context [if ?c then _ else _] =>
        destruct c; [injection H as H; subst; simpl; reflexivity | discriminate]
    end.
Qed.

(** ** 7.4: Notes list is invariant across transitions *)

Lemma notes_preserved :
  forall s s' tr,
    do_transition s tr = Some s' ->
    notes s' = notes s.
Proof.
  intros [p r mr ns ca oa] s' tr H.
  destruct p, tr;
    cbn [do_transition st_phase review_round max_review_rounds
         notes coder_approval observer_approval] in H;
    try discriminate;
    try (injection H as H; subst; simpl; reflexivity).
  - match type of H with
    | context [if ?c then _ else _] =>
        destruct c; [injection H as H; subst; simpl; reflexivity | discriminate]
    end.
Qed.

(** ** 7.5: Characterization of both_approved *)

Lemma both_approved_true_iff :
  forall s,
    both_approved s = true <->
    (exists ca oa,
       coder_approval s = Some ca /\ approved ca = true /\
       observer_approval s = Some oa /\ approved oa = true).
Proof.
  intros [p r mr ns ca oa]. unfold both_approved. simpl.
  split.
  - destruct ca as [[ca_b]|], oa as [[oa_b]|]; simpl;
      try discriminate.
    destruct ca_b, oa_b; simpl; try discriminate; intros _.
    exists (mk_approval true), (mk_approval true). auto.
  - intros [ca' [oa' [Hca [Hca_true [Hoa Hoa_true]]]]].
    rewrite Hca, Hoa. simpl. rewrite Hca_true, Hoa_true. reflexivity.
Qed.

(** ** 7.6: Blocking note properties *)

Lemma resolved_not_blocking :
  forall sev, is_blocking (mk_note sev true) = false.
Proof.
  intros sev. unfold is_blocking. simpl. reflexivity.
Qed.

Lemma low_not_blocking :
  forall resolved, is_blocking (mk_note Low resolved) = false.
Proof.
  intros []; reflexivity.
Qed.

Lemma medium_not_blocking :
  forall resolved, is_blocking (mk_note Medium resolved) = false.
Proof.
  intros []; reflexivity.
Qed.

Lemma critical_unresolved_is_blocking :
  is_blocking (mk_note Critical false) = true.
Proof. reflexivity. Qed.

Lemma high_unresolved_is_blocking :
  is_blocking (mk_note High false) = true.
Proof. reflexivity. Qed.

Lemma blocking_note_means_has_blocking :
  forall n ns_before ns_after p r mr ca oa,
    is_blocking n = true ->
    has_blocking_notes
      (mk_state p r mr (ns_before ++ n :: ns_after) ca oa) = true.
Proof.
  intros n ns_before ns_after p r mr ca oa Hblock.
  unfold has_blocking_notes. simpl.
  apply existsb_exists.
  exists n. split.
  - apply in_or_app. right. left. reflexivity.
  - exact Hblock.
Qed.

(** ** 7.7: Phase level is bounded for all states *)

Theorem phase_level_bounded :
  forall s, phase_level (st_phase s) <= 3.
Proof.
  intros s. destruct (st_phase s); simpl; lia.
Qed.


(** ** 7.8: Transition success/failure classification *)

(** Exactly which transitions succeed from each phase. *)

Lemma coding_valid_transitions :
  forall s, st_phase s = Coding ->
    (exists s', do_transition s Start_review = Some s') /\
    (exists s', do_transition s Timeout = Some s') /\
    (exists s', do_transition s Abort = Some s') /\
    do_transition s Start_iteration = None /\
    do_transition s Complete = None /\
    do_transition s Finalize = None.
Proof.
  intros [p r mr ns ca oa] Hp. simpl in Hp. subst.
  repeat split; try (eexists; reflexivity); reflexivity.
Qed.

Lemma review_valid_transitions :
  forall s, st_phase s = Review ->
    (exists s', do_transition s Start_iteration = Some s') /\
    (exists s', do_transition s Timeout = Some s') /\
    (exists s', do_transition s Abort = Some s') /\
    do_transition s Start_review = None /\
    do_transition s Finalize = None.
Proof.
  intros [p r mr ns ca oa] Hp. simpl in Hp. subst.
  repeat split; try (eexists; reflexivity); reflexivity.
Qed.

Lemma iteration_valid_transitions :
  forall s, st_phase s = Iteration ->
    (exists s', do_transition s Start_review = Some s') /\
    (exists s', do_transition s Timeout = Some s') /\
    (exists s', do_transition s Abort = Some s') /\
    do_transition s Start_iteration = None /\
    do_transition s Complete = None /\
    do_transition s Finalize = None.
Proof.
  intros [p r mr ns ca oa] Hp. simpl in Hp. subst.
  repeat split; try (eexists; reflexivity); reflexivity.
Qed.

Lemma completion_valid_transitions :
  forall s, st_phase s = Completion ->
    (exists s', do_transition s Finalize = Some s') /\
    (exists s', do_transition s Timeout = Some s') /\
    (exists s', do_transition s Abort = Some s') /\
    do_transition s Start_review = None /\
    do_transition s Start_iteration = None /\
    do_transition s Complete = None.
Proof.
  intros [p r mr ns ca oa] Hp. simpl in Hp. subst.
  repeat split; try (eexists; reflexivity); reflexivity.
Qed.

Lemma done_valid_transitions :
  forall s, st_phase s = Done ->
    (exists s', do_transition s Timeout = Some s') /\
    (exists s', do_transition s Abort = Some s') /\
    do_transition s Start_review = None /\
    do_transition s Start_iteration = None /\
    do_transition s Complete = None /\
    do_transition s Finalize = None.
Proof.
  intros [p r mr ns ca oa] Hp. simpl in Hp. subst.
  repeat split; try (eexists; reflexivity); reflexivity.
Qed.

(** ** 7.9: Approval lifecycle — approvals only cleared on Start_review *)

Lemma approvals_preserved_unless_start_review :
  forall s s' tr,
    tr <> Start_review ->
    do_transition s tr = Some s' ->
    coder_approval s' = coder_approval s /\
    observer_approval s' = observer_approval s.
Proof.
  intros [p r mr ns ca oa] s' tr Hne H.
  destruct p, tr;
    cbn [do_transition st_phase review_round max_review_rounds
         notes coder_approval observer_approval] in H;
    try discriminate;
    try (injection H as H; subst; simpl; auto);
    try (exfalso; apply Hne; reflexivity).
  - (* Review, Complete *)
    match type of H with
    | context [if ?c then _ else _] =>
        destruct c; [injection H as H; subst; simpl; auto | discriminate]
    end.
Qed.

(** ** 7.10: Done is a fixed point for Timeout and Abort *)

Lemma timeout_idempotent_on_done :
  forall s s',
    st_phase s = Done ->
    do_transition s Timeout = Some s' ->
    s' = s.
Proof.
  intros [p r mr ns ca oa] s' Hp H.
  simpl in Hp. subst.
  cbn [do_transition st_phase review_round max_review_rounds
       notes coder_approval observer_approval] in H.
  injection H as H. subst. reflexivity.
Qed.

Lemma abort_idempotent_on_done :
  forall s s',
    st_phase s = Done ->
    do_transition s Abort = Some s' ->
    s' = s.
Proof.
  intros [p r mr ns ca oa] s' Hp H.
  simpl in Hp. subst.
  cbn [do_transition st_phase review_round max_review_rounds
       notes coder_approval observer_approval] in H.
  injection H as H. subst. reflexivity.
Qed.

End PairCoding.
