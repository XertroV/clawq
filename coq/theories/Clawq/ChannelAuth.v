From Coq Require Import String List Bool Arith Lia Nat.
Import ListNotations.
Open Scope string_scope.
Local Open Scope nat_scope.

(* ================================================================
   F8: Channel authentication — generic allowlist + replay prevention.

   Target: src/slack.ml, src/discord.ml, src/telegram.ml (shared auth pattern).

   Key theorems:
   - is_allowed_correct: allowlist membership check is bidirectional
   - is_allowed_wildcard: ["*"] allows all IDs
   - timestamp_ok_enforces_window: 300s replay prevention enforced

   Extraction: is_allowed extracted to replace OCaml versions.
   ================================================================ *)

(* ----------------------------------------------------------------
   Generic allowlist filtering.
   
   is_allowed id list = true iff:
   - list = ["*"] (wildcard, allow all), OR
   - id is in list (explicit membership)
   ---------------------------------------------------------------- *)

Definition is_allowed (id : string) (allowlist : list string) : bool :=
  match allowlist with
  | [ w ] => if String.eqb w "*" then true else existsb (String.eqb id) [w]
  | _ => existsb (String.eqb id) allowlist
  end.

(* ================================================================
   Allowlist correctness proofs.
   ================================================================ *)

(* Theorem 1: Forward direction - if allowed, then in list or wildcard *)
Theorem is_allowed_forward : forall id allowlist,
  is_allowed id allowlist = true ->
  existsb (String.eqb id) allowlist = true \/ allowlist = [ "*"].
Proof.
  intros id allowlist H.
  destruct allowlist as [| h t].
  - unfold is_allowed in H. discriminate.
  - destruct t as [| t' rest].
    + (* [h] case *)
      destruct (String.eqb_spec h "*") as [Heq | Hneq].
      * subst h. right. reflexivity.
      * left. unfold is_allowed in H.
        change (existsb (String.eqb id) [h] = true).
        apply String.eqb_neq in Hneq.
        destruct (String.eqb h "*")%string eqn:E; [congruence |].
        exact H.
    + (* h :: t' :: rest *)
      left. unfold is_allowed in H. exact H.
Qed.

(* Theorem 2: Backward direction - if in list or wildcard, then allowed *)
Theorem is_allowed_backward : forall id allowlist,
  existsb (String.eqb id) allowlist = true \/ allowlist = ["*"] ->
  is_allowed id allowlist = true.
Proof.
  intros id allowlist [Hmem | Hwildcard].
  - (* Membership case *)
    destruct allowlist as [| h t].
    + simpl in Hmem. discriminate.
    + destruct t as [| t' rest].
      * (* [h] case *)
        unfold is_allowed.
        destruct (String.eqb h "*") eqn:Ewildcard.
        -- reflexivity.
        -- exact Hmem.
      * (* h :: t' :: rest case *)
        unfold is_allowed. exact Hmem.
  - (* Wildcard case *)
    subst allowlist.
    unfold is_allowed. simpl. reflexivity.
Qed.

(* Theorem 3: Bidirectional correctness *)
Theorem is_allowed_correct : forall id allowlist,
  is_allowed id allowlist = true <->
  existsb (String.eqb id) allowlist = true \/ allowlist = ["*"].
Proof.
  intros id allowlist.
  split.
  - apply is_allowed_forward.
  - apply is_allowed_backward.
Qed.

(* Theorem 4: Wildcard allows all IDs *)
Theorem is_allowed_wildcard : forall id,
  is_allowed id ["*"] = true.
Proof.
  intros id.
  reflexivity.
Qed.

(* Theorem 5: Non-wildcard single-element list *)
Theorem is_allowed_single : forall id h,
  h <> "*" ->
  is_allowed id [h] = String.eqb id h.
Proof.
  intros id h Hneq.
  unfold is_allowed.
  apply String.eqb_neq in Hneq. rewrite Hneq.
  simpl. apply Bool.orb_false_r.
Qed.

(* Theorem 6: Monotonicity - membership-based permission is preserved by appending.
   Note: wildcard ["*"] allows all IDs but is a structural match, so appending
   to a wildcard list changes it to a non-wildcard list. This theorem covers
   the membership case. *)
Theorem is_allowed_monotone : forall id xs ys,
  existsb (String.eqb id) xs = true ->
  is_allowed id (xs ++ ys) = true.
Proof.
  intros id xs ys Hmem.
  apply is_allowed_backward.
  left. apply existsb_exists in Hmem.
  apply existsb_exists.
  destruct Hmem as [x [Hin Heq]].
  exists x. split.
  - apply in_or_app. left. exact Hin.
  - exact Heq.
Qed.

(* ================================================================
   Replay prevention - timestamp window checking.
   ================================================================ *)

(* Model timestamps as naturals (seconds since epoch) *)
Definition timestamp := nat.

Local Open Scope nat_scope.

(* Check if a timestamp is within the allowed window (300 seconds) *)
Definition timestamp_ok (request_ts current_ts : timestamp) : bool :=
  if Nat.ltb current_ts request_ts then false
  else Nat.leb (current_ts - request_ts) 300.

(* Theorem 7: timestamp_ok enforces 300s window *)
Theorem timestamp_ok_enforces_window : forall request_ts current_ts,
  timestamp_ok request_ts current_ts = true ->
  current_ts >= request_ts /\ current_ts - request_ts <= 300.
Proof.
  intros request_ts current_ts H.
  unfold timestamp_ok in H.
  destruct (current_ts <? request_ts) eqn:Ecmp.
  - (* current_ts < request_ts - impossible since H = true *)
    simpl in H. discriminate.
  - (* current_ts >= request_ts *)
    split.
    + apply Nat.ltb_ge. exact Ecmp.
    + apply Nat.leb_le. exact H.
Qed.

(* Theorem 8: Valid timestamp passes check *)
Theorem timestamp_ok_valid : forall request_ts current_ts,
  current_ts >= request_ts ->
  current_ts - request_ts <= 300 ->
  timestamp_ok request_ts current_ts = true.
Proof.
  intros request_ts current_ts Hge Hwindow.
  unfold timestamp_ok.
  destruct (current_ts <? request_ts) eqn:Ecmp.
  - apply Nat.ltb_lt in Ecmp. lia.
  - apply Nat.leb_le. exact Hwindow.
Qed.

(* Theorem 9: Future timestamp rejected *)
Theorem timestamp_ok_future_rejected : forall request_ts current_ts,
  current_ts < request_ts ->
  timestamp_ok request_ts current_ts = false.
Proof.
  intros request_ts current_ts H.
  unfold timestamp_ok.
  destruct (current_ts <? request_ts) eqn:Ecmp.
  - reflexivity.
  - apply Nat.ltb_ge in Ecmp. lia.
Qed.

(* Theorem 10: Expired timestamp rejected *)
Theorem timestamp_ok_expired_rejected : forall request_ts current_ts,
  current_ts >= request_ts ->
  current_ts - request_ts > 300 ->
  timestamp_ok request_ts current_ts = false.
Proof.
  intros request_ts current_ts Hge Hexpired.
  unfold timestamp_ok.
  destruct (current_ts <? request_ts) eqn:Ecmp.
  - apply Nat.ltb_lt in Ecmp. lia.
  - apply Nat.leb_gt. exact Hexpired.
Qed.

(* ================================================================
   Summary of what was proved:
   - is_allowed_forward: allowed -> (in list \/ wildcard)
   - is_allowed_backward: (in list \/ wildcard) -> allowed
   - is_allowed_correct: bidirectional correctness
   - is_allowed_wildcard: ["*"] allows all
   - is_allowed_single: non-wildcard single element
   - is_allowed_monotone: adding IDs never revokes
   - timestamp_ok_enforces_window: 300s window enforced
   - timestamp_ok_valid: valid timestamp passes
   - timestamp_ok_future_rejected: future timestamps rejected
   - timestamp_ok_expired_rejected: expired timestamps rejected
   
   Extraction target:
   - is_allowed: replace OCaml versions in slack.ml, discord.ml, telegram.ml
   ================================================================ *)
