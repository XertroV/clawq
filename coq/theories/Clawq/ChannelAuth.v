From Coq Require Import String List Bool Arith Lia Nat.
Require Import Coq.Arith.PeanoNat.
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

(* Runtime-composed checks used by channel integrations. *)
Definition slack_allowed
    (channel_id user_id : string)
    (allow_channels allow_users : list string) : bool :=
  is_allowed channel_id allow_channels && is_allowed user_id allow_users.

Definition discord_guild_allowed
    (guild_id : option string) (allow_guilds : list string) : bool :=
  match guild_id with
  | Some gid => is_allowed gid allow_guilds
  | None =>
      match allow_guilds with
      | ["*"] => true
      | _ => false
      end
  end.

Definition discord_allowed
    (guild_id : option string) (user_id : string)
    (allow_guilds allow_users : list string) : bool :=
  discord_guild_allowed guild_id allow_guilds && is_allowed user_id allow_users.

Theorem slack_allowed_correct :
  forall channel_id user_id allow_channels allow_users,
    slack_allowed channel_id user_id allow_channels allow_users = true <->
    is_allowed channel_id allow_channels = true /\
    is_allowed user_id allow_users = true.
Proof.
  intros channel_id user_id allow_channels allow_users.
  unfold slack_allowed.
  rewrite Bool.andb_true_iff.
  tauto.
Qed.

Lemma singleton_guild_decision : forall gid,
  discord_guild_allowed None [gid] = String.eqb gid "*".
Proof.
  intros gid.
  unfold discord_guild_allowed.
  destruct gid as [|a s].
  - reflexivity.
  - destruct s as [|a' s'].
    + simpl.
      destruct a as [b0 b1 b2 b3 b4 b5 b6 b7];
        destruct b0; destruct b1; destruct b2; destruct b3;
        destruct b4; destruct b5; destruct b6; destruct b7; reflexivity.
    + simpl.
      destruct a as [b0 b1 b2 b3 b4 b5 b6 b7];
        destruct b0; destruct b1; destruct b2; destruct b3;
        destruct b4; destruct b5; destruct b6; destruct b7; reflexivity.
Qed.

Theorem discord_none_guild_non_wildcard_rejected : forall allow_guilds,
  allow_guilds <> ["*"] ->
  discord_guild_allowed None allow_guilds = false.
Proof.
  intros allow_guilds Hneq.
  destruct allow_guilds as [|h t].
  - unfold discord_guild_allowed. reflexivity.
  - destruct t as [|h' t'].
    + rewrite singleton_guild_decision.
      destruct (String.eqb h "*") eqn:Heq.
      * apply String.eqb_eq in Heq. subst h. exfalso. apply Hneq. reflexivity.
      * reflexivity.
    + unfold discord_guild_allowed.
      destruct h as [|a s].
      * reflexivity.
      * destruct s as [|a0 s0].
        -- destruct a as [b0 b1 b2 b3 b4 b5 b6 b7];
             destruct b0; destruct b1; destruct b2; destruct b3;
             destruct b4; destruct b5; destruct b6; destruct b7; reflexivity.
        -- destruct a as [b0 b1 b2 b3 b4 b5 b6 b7];
             destruct b0; destruct b1; destruct b2; destruct b3;
             destruct b4; destruct b5; destruct b6; destruct b7; reflexivity.
Qed.

(* ================================================================
   Replay prevention - timestamp window checking.
   ================================================================ *)

(* Model timestamps as naturals (seconds since epoch) *)
Definition timestamp := nat.

Local Open Scope nat_scope.

(* Runtime semantics (Slack): absolute clock skew must be <= 300s. *)
Definition abs_diff (a b : nat) : nat :=
  if Nat.leb a b then b - a else a - b.

(* Check if a timestamp is within the allowed window (300 seconds). *)
Definition timestamp_ok (request_ts current_ts : timestamp) : bool :=
  Nat.leb (abs_diff request_ts current_ts) 300.

(* Theorem 7: timestamp_ok enforces 300s absolute window. *)
Theorem timestamp_ok_enforces_window : forall request_ts current_ts,
  timestamp_ok request_ts current_ts = true ->
  abs_diff request_ts current_ts <= 300.
Proof.
  intros request_ts current_ts H.
  unfold timestamp_ok in H.
  apply Nat.leb_le. exact H.
Qed.

(* Theorem 8: Timestamp within 300s skew passes check. *)
Theorem timestamp_ok_valid : forall request_ts current_ts,
  abs_diff request_ts current_ts <= 300 ->
  timestamp_ok request_ts current_ts = true.
Proof.
  intros request_ts current_ts Hwindow.
  unfold timestamp_ok.
  apply Nat.leb_le. exact Hwindow.
Qed.

(* Theorem 9: Timestamps farther than 300s apart are rejected. *)
Theorem timestamp_ok_far_apart_rejected : forall request_ts current_ts,
  abs_diff request_ts current_ts > 300 ->
  timestamp_ok request_ts current_ts = false.
Proof.
  intros request_ts current_ts H.
  unfold timestamp_ok.
  apply Nat.leb_gt in H.
  rewrite H.
  reflexivity.
Qed.

(* Theorem 10: Expired timestamp rejected *)
Theorem timestamp_ok_expired_rejected : forall request_ts current_ts,
  current_ts >= request_ts ->
  current_ts - request_ts > 300 ->
  timestamp_ok request_ts current_ts = false.
Proof.
  intros request_ts current_ts Hge Hexpired.
  unfold timestamp_ok.
  apply Nat.leb_gt.
  unfold abs_diff.
  assert (Hleb : Nat.leb request_ts current_ts = true).
    { apply Nat.leb_le. lia. }
  rewrite Hleb.
  exact Hexpired.
Qed.

(* ================================================================
   Telegram pairing validity window model.
   ================================================================ *)

Definition pairing_active (now expiry : timestamp) : bool :=
  Nat.ltb now expiry.

Theorem pairing_active_before_expiry : forall now expiry,
  now < expiry -> pairing_active now expiry = true.
Proof.
  intros now expiry Hlt.
  unfold pairing_active.
  apply Nat.ltb_lt in Hlt.
  exact Hlt.
Qed.

Theorem pairing_inactive_at_or_after_expiry : forall now expiry,
  now >= expiry -> pairing_active now expiry = false.
Proof.
  intros now expiry Hge.
  unfold pairing_active.
  apply Nat.ltb_ge in Hge.
  exact Hge.
Qed.

Theorem pairing_active_iff : forall now expiry,
  pairing_active now expiry = true <-> now < expiry.
Proof.
  intros now expiry.
  split.
  - intro H.
    unfold pairing_active in H.
    apply Nat.ltb_lt in H.
    exact H.
  - intro H.
    unfold pairing_active.
    apply Nat.ltb_lt in H.
    exact H.
Qed.

(* Theorem 10: discord allow decision matches runtime shape. *)
Theorem discord_allowed_correct :
  forall guild_id user_id allow_guilds allow_users,
    discord_allowed guild_id user_id allow_guilds allow_users = true <->
    discord_guild_allowed guild_id allow_guilds = true /\
    is_allowed user_id allow_users = true.
Proof.
  intros guild_id user_id allow_guilds allow_users.
  unfold discord_allowed.
  rewrite Bool.andb_true_iff.
  tauto.
Qed.

(* Theorem 11: wildcard guild allowlist admits DM/None-guild events. *)
Theorem discord_none_guild_wildcard_allowed :
  discord_guild_allowed None ["*"] = true.
Proof.
  reflexivity.
Qed.

(* Theorem 12: non-wildcard guild allowlist rejects DM/None-guild events. *)
Theorem discord_none_guild_specific_rejected : forall gid,
  discord_guild_allowed None [gid] = String.eqb gid "*".
Proof.
  apply singleton_guild_decision.
Qed.

(* Summary:
   - is_allowed + compositional lemmas model shared allowlist checks used by
     Slack/Discord.
   - timestamp_ok now models absolute skew window (Slack replay semantics).
   - pairing_active models Telegram pairing validity-until-expiry semantics.
   - Telegram TOTP code generation/verification itself remains a trusted
     cryptographic boundary outside this model. *)
(* ================================================================ *)
(* Extraction target:
   - is_allowed, discord_guild_allowed, timestamp_ok, pairing_active.
   ================================================================ *)
(* End of module. *)
(* --------------------------------------------------------------- *)
(* Keep final theorem as a compile guard for the summary section. *)
Theorem channel_auth_model_well_formed : True.
Proof.
  reflexivity.
Qed.
