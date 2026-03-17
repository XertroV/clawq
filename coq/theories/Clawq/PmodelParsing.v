(** Pmodel Canonical Format Parsing — Formal Verification

    Spec-only Coq formalization of the provider:model format parsing
    from src/pmodel.ml. Proves correctness of format classification,
    canonical normalization, and deprecation warnings.

    No extraction needed.
*)

Require Import Coq.Bool.Bool.
Require Import Coq.Arith.Arith.
Require Import Coq.Arith.PeanoNat.
Require Import Coq.Lists.List.
Require Import Lia.
Import ListNotations.

Module PmodelParsing.

(** * Types *)

(** Model format classification *)
Inductive format : Type :=
  | Canonical  (* provider:model *)
  | Legacy     (* provider/model — deprecated *)
  | Bare.      (* model only — deprecated *)

(** Parsed model reference *)
Record pmodel : Type := mk_pmodel {
  pm_provider : nat;  (* provider ID — nat for simplicity *)
  pm_model : nat;     (* model ID *)
}.

(** Flexible parse result (may lack provider) *)
Record flexible : Type := mk_flexible {
  fl_provider : option nat;
  fl_model : nat;
  fl_format : format;
}.

(** * Parse Functions *)

(** Canonical parse: requires both provider and model. *)
Definition parse (provider model : nat) : pmodel :=
  mk_pmodel provider model.

(** Parse flexible: classify format and extract components. *)
Definition parse_flexible (f : flexible) : flexible := f.

(** Convert flexible to canonical, using default_provider for Bare. *)
Definition flexible_to_canonical (f : flexible) (default_provider : option nat)
    : option pmodel :=
  match fl_format f with
  | Canonical =>
      match fl_provider f with
      | Some p => Some (mk_pmodel p (fl_model f))
      | None => None  (* ill-formed canonical *)
      end
  | Legacy =>
      match fl_provider f with
      | Some p => Some (mk_pmodel p (fl_model f))
      | None => None  (* ill-formed legacy *)
      end
  | Bare =>
      match default_provider with
      | Some dp => Some (mk_pmodel dp (fl_model f))
      | None => None
      end
  end.

(** Deprecation warning: returns true iff format is non-canonical. *)
Definition needs_deprecation_warning (f : flexible) : bool :=
  match fl_format f with
  | Canonical => false
  | Legacy => true
  | Bare => true
  end.

(** * Invariant Theorems *)

(** Theorem 1: Canonical format with provider always converts successfully. *)
Theorem canonical_always_converts :
  forall p m,
    flexible_to_canonical
      (mk_flexible (Some p) m Canonical) None = Some (mk_pmodel p m).
Proof.
  intros. reflexivity.
Qed.

(** Theorem 2: Canonical conversion is idempotent in meaning —
    converting a Canonical flexible yields the same provider and model. *)
Theorem canonical_preserves_components :
  forall f pm dp,
    fl_format f = Canonical ->
    flexible_to_canonical f dp = Some pm ->
    pm_provider pm = match fl_provider f with Some p => p | None => 0 end /\
    pm_model pm = fl_model f.
Proof.
  intros [fp fm ff] pm dp Hfmt H.
  simpl in Hfmt. subst ff.
  simpl in H. destruct fp; [| discriminate].
  injection H as H. subst. simpl. auto.
Qed.

(** Theorem 3: Legacy conversion preserves components. *)
Theorem legacy_preserves_components :
  forall p m dp,
    flexible_to_canonical (mk_flexible (Some p) m Legacy) dp =
      Some (mk_pmodel p m).
Proof.
  intros. reflexivity.
Qed.

(** Theorem 4: Bare conversion requires default_provider. *)
Theorem bare_requires_default :
  forall m,
    flexible_to_canonical (mk_flexible None m Bare) None = None.
Proof.
  intros. reflexivity.
Qed.

Theorem bare_with_default_succeeds :
  forall m dp,
    flexible_to_canonical (mk_flexible None m Bare) (Some dp) =
      Some (mk_pmodel dp m).
Proof.
  intros. reflexivity.
Qed.

(** Theorem 5: Deprecation warning is issued iff format is non-canonical. *)
Theorem deprecation_iff_non_canonical :
  forall f,
    needs_deprecation_warning f = true <-> fl_format f <> Canonical.
Proof.
  intros [fp fm ff]. simpl. destruct ff; split; intro H;
    try reflexivity; try discriminate;
    try (intro Habs; discriminate);
    try (exfalso; apply H; reflexivity).
Qed.

(** Theorem 6: No deprecation warning for canonical format. *)
Theorem canonical_no_warning :
  forall f,
    fl_format f = Canonical ->
    needs_deprecation_warning f = false.
Proof.
  intros [fp fm ff] H. simpl in H. subst. reflexivity.
Qed.

(** Theorem 7: Format classification is exhaustive and exclusive. *)
Theorem format_exclusive :
  forall fmt,
    (fmt = Canonical /\ fmt <> Legacy /\ fmt <> Bare) \/
    (fmt <> Canonical /\ fmt = Legacy /\ fmt <> Bare) \/
    (fmt <> Canonical /\ fmt <> Legacy /\ fmt = Bare).
Proof.
  intros fmt. destruct fmt.
  - left. repeat split; discriminate.
  - right. left. repeat split; discriminate.
  - right. right. repeat split; discriminate.
Qed.

(** Theorem 8: Canonical format produces same provider regardless of
    default_provider argument. *)
Theorem canonical_ignores_default :
  forall p m dp1 dp2,
    flexible_to_canonical (mk_flexible (Some p) m Canonical) dp1 =
    flexible_to_canonical (mk_flexible (Some p) m Canonical) dp2.
Proof.
  intros. reflexivity.
Qed.

(** Theorem 9: Legacy format produces same provider regardless of
    default_provider argument. *)
Theorem legacy_ignores_default :
  forall p m dp1 dp2,
    flexible_to_canonical (mk_flexible (Some p) m Legacy) dp1 =
    flexible_to_canonical (mk_flexible (Some p) m Legacy) dp2.
Proof.
  intros. reflexivity.
Qed.

(** Theorem 10: Bare format uses exactly the default provider. *)
Theorem bare_uses_default_provider :
  forall m dp pm,
    flexible_to_canonical (mk_flexible None m Bare) (Some dp) = Some pm ->
    pm_provider pm = dp.
Proof.
  intros m dp pm H. simpl in H. injection H as H. subst. reflexivity.
Qed.

(** Theorem 11: All successful conversions produce non-None results
    with matching model field. *)
Theorem conversion_preserves_model :
  forall f dp pm,
    flexible_to_canonical f dp = Some pm ->
    pm_model pm = fl_model f.
Proof.
  intros [fp fm ff] dp pm H.
  destruct ff; simpl in H.
  - destruct fp; [injection H as H; subst; reflexivity | discriminate].
  - destruct fp; [injection H as H; subst; reflexivity | discriminate].
  - destruct dp; [injection H as H; subst; reflexivity | discriminate].
Qed.

(** Theorem 12: Conversion deterministic — same inputs same outputs. *)
Lemma conversion_deterministic :
  forall f dp r1 r2,
    flexible_to_canonical f dp = r1 ->
    flexible_to_canonical f dp = r2 ->
    r1 = r2.
Proof.
  intros. rewrite <- H. exact H0.
Qed.

End PmodelParsing.
