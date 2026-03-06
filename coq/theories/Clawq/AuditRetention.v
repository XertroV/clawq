From Coq Require Import String List Bool Arith Lia.
From Clawq Require Import AuditChain.
Import ListNotations.

(* Use nat_scope for arithmetic, but list_scope for list operations *)
Local Open Scope nat_scope.
Local Open Scope list_scope.

(* ================================================================
   F9: Audit retention safety — formal model of purge operations
   that preserve chain validity.

   Proves that purge_by_count (keep newest n) and purge_by_age
   (delete old entries) preserve chain validity.
   ================================================================ *)

(* ----------------------------------------------------------------
   Purge operations (pure functional model)
   ---------------------------------------------------------------- *)

(* Purge by count: keep only the last n entries.
   This matches the SQL: DELETE WHERE id NOT IN (SELECT ... ORDER BY id DESC LIMIT n)
   which is equivalent to dropping the first length(entries) - n items. *)
Definition purge_by_count (n : nat) (entries : list audit_entry) : list audit_entry :=
  skipn (length entries - n) entries.

(* Check if a timestamp is >= cutoff (string comparison, abstract)
   In practice: timestamp >= datetime('now', '-max_age_days') *)
Parameter timestamp_ge : string -> string -> bool.

(* Purge by age: keep only entries with timestamp >= cutoff *)
Definition purge_by_age (cutoff : string) (entries : list audit_entry) : list audit_entry :=
  filter (fun e => timestamp_ge (ae_timestamp e) cutoff) entries.

(* ----------------------------------------------------------------
   Purge_by_count properties
   ---------------------------------------------------------------- *)

(* P1: purge_by_count 0 always returns empty *)
Lemma purge_by_count_0 : forall entries,
  purge_by_count 0 entries = [].
Proof.
  intros entries.
  unfold purge_by_count.
  rewrite Nat.sub_0_r.
  apply skipn_all.
Qed.

(* P2: purge_by_count on empty list returns empty *)
Lemma purge_by_count_nil : forall n,
  purge_by_count n [] = [].
Proof.
  intros n.
  unfold purge_by_count.
  simpl.
  reflexivity.
Qed.

(* P3: purge_by_count produces a suffix of the original list *)
Lemma purge_by_count_suffix : forall n entries,
  exists prefix, entries = prefix ++ purge_by_count n entries.
Proof.
  intros n entries.
  exists (firstn (length entries - n) entries).
  unfold purge_by_count.
  symmetry.
  apply firstn_skipn.
Qed.

(* P4: purge_by_count keeps at most n entries *)
Lemma purge_by_count_length : forall n entries,
  length (purge_by_count n entries) <= n.
Proof.
  intros n entries.
  unfold purge_by_count.
  rewrite skipn_length.
  lia.
Qed.

(* Naive statement (false): verifying the retained suffix with the original
   prev_sig. The correct formulation threads the anchor induced by the dropped
   prefix through last_sig. See purge_by_count_preserves_validity below. *)

(* Helper: verify_chain is monotone - a suffix of a valid chain is valid (with correct prev_sig) *)
Lemma verify_chain_suffix_valid : forall key prev_sig h rest,
  verify_chain key prev_sig (h :: rest) = true ->
  verify_chain key (Some (ae_signature h)) rest = true.
Proof.
  intros key prev_sig h rest Hvalid.
  simpl in Hvalid.
  apply Bool.andb_true_iff in Hvalid.
  destruct Hvalid as [_ Hvalid_rest].
  exact Hvalid_rest.
Qed.

(* Better formulation: purge preserves validity of suffix *)
(* The purged chain is valid with the correct starting prev_sig *)
(* Simpler theorem: suffix of valid chain is valid (with appropriate prev_sig) *)
Lemma suffix_preserves_validity : forall key prefix suffix prev_sig,
  verify_chain key prev_sig (prefix ++ suffix) = true ->
  verify_chain key (last_sig prev_sig prefix) suffix = true.
Proof.
  intros key prefix suffix prev_sig Hvalid.
  revert prev_sig Hvalid.
  induction prefix as [| h prefix' IH]; intros prev_sig Hvalid.
  - simpl. exact Hvalid.
  - simpl in Hvalid.
    apply Bool.andb_true_iff in Hvalid.
    destruct Hvalid as [_ Hvalid_rest].
    simpl.
    apply IH. exact Hvalid_rest.
Qed.

(* Main theorem: purge preserves validity with the anchor induced by the
   removed prefix. *)
Theorem purge_by_count_preserves_validity : forall key prev_sig n entries,
  verify_chain key prev_sig entries = true ->
  exists prefix,
    entries = prefix ++ purge_by_count n entries /\
    verify_chain key (last_sig prev_sig prefix) (purge_by_count n entries) = true.
Proof.
  intros key prev_sig n entries Hvalid.
  destruct (purge_by_count_suffix n entries) as [prefix Heq].
  exists prefix.
  split.
  - exact Heq.
  - rewrite Heq in Hvalid.
    apply suffix_preserves_validity. exact Hvalid.
Qed.

(* Convenience specialization for genesis-anchored chains. *)
Corollary purge_by_count_valid_suffix : forall key n entries,
  verify_chain key None entries = true ->
  forall prefix, entries = prefix ++ purge_by_count n entries ->
  verify_chain key (last_sig None prefix) (purge_by_count n entries) = true.
Proof.
  intros key n entries Hvalid prefix Heq.
  rewrite Heq in Hvalid.
  apply suffix_preserves_validity. exact Hvalid.
Qed.

(* Convenience existential form for the common genesis case. *)
Corollary purge_by_count_valid : forall key n entries,
  verify_chain key None entries = true ->
  exists prefix,
    entries = prefix ++ purge_by_count n entries /\
    verify_chain key (last_sig None prefix) (purge_by_count n entries) = true.
Proof.
  intros key n entries Hvalid.
  destruct (purge_by_count_preserves_validity key None n entries Hvalid)
    as [prefix [Heq Hsuffix]].
  exists prefix.
  split; assumption.
Qed.

(* ----------------------------------------------------------------
   Purge_by_age properties
   ---------------------------------------------------------------- *)

(* P6: purge_by_age produces a sublist (preserves order, possibly removes) *)
Lemma purge_by_age_sublist : forall cutoff entries,
  forall e, In e (purge_by_age cutoff entries) -> In e entries.
Proof.
  intros cutoff entries e Hin.
  unfold purge_by_age in Hin.
  apply filter_In in Hin.
  destruct Hin as [Hin _].
  exact Hin.
Qed.

(* P7: purge_by_age keeps only entries passing filter *)
Lemma purge_by_age_filter : forall cutoff entries e,
  In e (purge_by_age cutoff entries) ->
  timestamp_ge (ae_timestamp e) cutoff = true.
Proof.
  intros cutoff entries e Hin.
  unfold purge_by_age in Hin.
  apply filter_In in Hin.
  destruct Hin as [_ Hge].
  exact Hge.
Qed.

(* P8: purge_by_age on empty list is empty *)
Lemma purge_by_age_nil : forall cutoff,
  purge_by_age cutoff [] = [].
Proof.
  reflexivity.
Qed.

(* P9: purge_by_age preserves validity only when the runtime semantics really
   remove a prefix and retain a suffix. The runtime therefore retains only the
   newest contiguous suffix satisfying the retention cutoff. *)
Definition age_purge_keeps_suffix (cutoff : string) (entries : list audit_entry) : Prop :=
  exists prefix, entries = prefix ++ purge_by_age cutoff entries.

Theorem purge_by_age_preserves_validity : forall key prev_sig cutoff entries,
  verify_chain key prev_sig entries = true ->
  age_purge_keeps_suffix cutoff entries ->
  exists prefix,
    entries = prefix ++ purge_by_age cutoff entries /\
    verify_chain key (last_sig prev_sig prefix) (purge_by_age cutoff entries) = true.
Proof.
  intros key prev_sig cutoff entries Hvalid [prefix Heq].
  exists prefix.
  split.
  - exact Heq.
  - rewrite Heq in Hvalid.
    apply suffix_preserves_validity. exact Hvalid.
Qed.

(* ----------------------------------------------------------------
   Combined purge: apply both policies
   ---------------------------------------------------------------- *)

Definition purge (max_entries : nat) (cutoff : string) (entries : list audit_entry) :=
  purge_by_count max_entries (purge_by_age cutoff entries).

(* P10: Combined purge preserves validity when age purge keeps a suffix. *)
Theorem purge_preserves_validity : forall key max_entries cutoff entries,
  verify_chain key None entries = true ->
  age_purge_keeps_suffix cutoff entries ->
  exists prefix, 
    verify_chain key (last_sig None prefix) (purge max_entries cutoff entries) = true.
Proof.
  intros key max_entries cutoff entries Hvalid [age_prefix Hage].
  unfold purge.
  rewrite Hage in Hvalid.
  assert (Hage_valid :
    verify_chain key (last_sig None age_prefix) (purge_by_age cutoff entries) = true).
  {
    apply suffix_preserves_validity.
    exact Hvalid.
  }
  destruct
    (purge_by_count_preserves_validity key (last_sig None age_prefix)
       max_entries (purge_by_age cutoff entries) Hage_valid)
    as [count_prefix [_ Hcount_valid]].
  exists (age_prefix ++ count_prefix).
  rewrite last_sig_app.
  exact Hcount_valid.
Qed.
