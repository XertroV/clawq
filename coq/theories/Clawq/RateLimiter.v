From Coq Require Import ZArith Bool Lia.

(* ================================================================
   F4: Token bucket rate limiter — formal specification.

   Uses scaled integers so refill / try_consume can be extracted to
   OCaml without a rational arithmetic dependency.

   Tokens are represented in 1/60000-token units. With timestamps in
   milliseconds, one millisecond at one token/minute adds exactly one
   scaled unit, so refill is plain integer arithmetic.
   ================================================================ *)

Open Scope Z_scope.

Module RateLimiter.

(* ----------------------------------------------------------------
   Units
   ---------------------------------------------------------------- *)

Definition token_scale : Z := 60000.
Definition one_token : Z := token_scale.

(* ----------------------------------------------------------------
   Data model
   ---------------------------------------------------------------- *)

Record limiter_config := {
  rate_per_minute : Z;    (* whole tokens granted per minute *)
  max_tokens      : Z     (* maximum bucket capacity, scaled by token_scale *)
}.

Record bucket := {
  tokens      : Z;        (* current token count, scaled by token_scale *)
  last_refill : Z         (* timestamp of last refill, in milliseconds *)
}.

(* ----------------------------------------------------------------
   Operations
   ---------------------------------------------------------------- *)

(* Refill the bucket based on elapsed time since last refill *)
Definition refill (cfg : limiter_config) (b : bucket) (now : Z) : bucket :=
  let elapsed := now - last_refill b in
  let added := elapsed * rate_per_minute cfg in
  let new_tok := tokens b + added in
  let capped := if new_tok <=? max_tokens cfg then new_tok
                else max_tokens cfg in
  {| tokens := capped; last_refill := now |}.

(* Try to consume one token. Returns (allowed, new_bucket). *)
Definition try_consume (cfg : limiter_config) (b : bucket) (now : Z)
    : bool * bucket :=
  let b' := refill cfg b now in
  if one_token <=? tokens b' then
    (true,
     {| tokens := tokens b' - one_token; last_refill := last_refill b' |})
  else
    (false, b').

(* ================================================================
   Invariants and proofs
   ================================================================ *)

(* P1: After refill, tokens never exceed max_tokens *)
Theorem refill_tokens_bounded : forall cfg b now,
  tokens (refill cfg b now) <= max_tokens cfg.
Proof.
  intros cfg b now. unfold refill. simpl.
  case_eq
    ((tokens b + (now - last_refill b) * rate_per_minute cfg)
       <=? max_tokens cfg);
    intro H.
  - apply Z.leb_le in H. exact H.
  - lia.
Qed.

(* P2: After refill with positive elapsed time, tokens are non-decreasing
   when bucket starts at most max_tokens (i.e., not in degenerate state). *)
Theorem refill_monotone : forall cfg b now,
  0 <= now - last_refill b ->
  0 <= rate_per_minute cfg ->
  tokens b <= max_tokens cfg ->
  tokens b <= tokens (refill cfg b now).
Proof.
  intros cfg b now Htime Hrate Hmax.
  unfold refill. simpl.
  case_eq
    ((tokens b + (now - last_refill b) * rate_per_minute cfg)
       <=? max_tokens cfg);
    intro Hcap.
  - apply Z.leb_le in Hcap.
    assert (Hadd : 0 <= (now - last_refill b) * rate_per_minute cfg).
    { apply Z.mul_nonneg_nonneg; assumption. }
    lia.
  - exact Hmax.
Qed.

(* P3: try_consume: if allowed, resulting tokens = refilled tokens - 1 *)
Theorem consume_decreases_by_one : forall cfg b now b',
  try_consume cfg b now = (true, b') ->
  tokens b' = tokens (refill cfg b now) - one_token.
Proof.
  intros cfg b now b' H.
  unfold try_consume in H.
  case_eq (one_token <=? tokens (refill cfg b now)); intro Hge;
    rewrite Hge in H.
  - injection H as Hb. rewrite <- Hb. simpl. reflexivity.
  - discriminate H.
Qed.

(* P4: try_consume: if denied, bucket state is unchanged after refill *)
Theorem consume_denied_unchanged : forall cfg b now b',
  try_consume cfg b now = (false, b') ->
  b' = refill cfg b now.
Proof.
  intros cfg b now b' H.
  unfold try_consume in H.
  case_eq (one_token <=? tokens (refill cfg b now)); intro Hge;
    rewrite Hge in H.
  - discriminate H.
  - injection H as Hb. rewrite <- Hb. reflexivity.
Qed.

(* P5: try_consume: if allowed, refilled bucket had at least 1 token *)
Theorem consume_requires_token : forall cfg b now b',
  try_consume cfg b now = (true, b') ->
  one_token <= tokens (refill cfg b now).
Proof.
  intros cfg b now b' H.
  unfold try_consume in H.
  case_eq (one_token <=? tokens (refill cfg b now)); intro Hge;
    rewrite Hge in H.
  - apply Z.leb_le in Hge. exact Hge.
  - discriminate H.
Qed.

(* P6: Tokens after consume are non-negative, given non-negative start *)
Theorem consume_tokens_nonneg : forall cfg b now b',
  try_consume cfg b now = (true, b') ->
  0 <= tokens (refill cfg b now) ->
  0 <= tokens b'.
Proof.
  intros cfg b now b' Hcons _.
  rewrite (consume_decreases_by_one cfg b now b' Hcons).
  assert (H1 : one_token <= tokens (refill cfg b now))
    by exact (consume_requires_token cfg b now b' Hcons).
  lia.
Qed.

(* P7: Refilling at the same time is idempotent *)
Theorem refill_same_time_idempotent : forall cfg b now,
  refill cfg (refill cfg b now) now = refill cfg b now.
Proof.
  intros cfg b now.
  unfold refill at 1 3. simpl.
  destruct ((tokens b + (now - last_refill b) * rate_per_minute cfg)
              <=? max_tokens cfg) eqn:Hinner; simpl.
  - (* inner <= max: tokens are the sum *)
    replace (now - now) with 0 by lia.
    replace (0 * rate_per_minute cfg) with 0 by lia.
    apply Z.leb_le in Hinner.
    replace (tokens b + (now - last_refill b) * rate_per_minute cfg + 0)
      with (tokens b + (now - last_refill b) * rate_per_minute cfg) by lia.
    assert (Hle : (tokens b + (now - last_refill b) * rate_per_minute cfg
                     <=? max_tokens cfg) = true) by (apply Z.leb_le; lia).
    rewrite Hle. reflexivity.
  - (* inner > max: capped to max_tokens *)
    replace (now - now) with 0 by lia.
    replace (0 * rate_per_minute cfg) with 0 by lia.
    replace (max_tokens cfg + 0) with (max_tokens cfg) by lia.
    assert (Hle : (max_tokens cfg <=? max_tokens cfg) = true)
      by (apply Z.leb_le; lia).
    rewrite Hle. reflexivity.
Qed.

(* P8: After consume, tokens are still bounded by max *)
Theorem consume_tokens_bounded : forall cfg b now allowed b',
  try_consume cfg b now = (allowed, b') ->
  tokens b' <= max_tokens cfg.
Proof.
  intros cfg b now allowed b' H.
  destruct allowed.
  - (* allowed = true *)
    assert (Hdec := consume_decreases_by_one cfg b now b' H).
    assert (Hbound := refill_tokens_bounded cfg b now).
    rewrite Hdec. unfold one_token, token_scale. lia.
  - (* allowed = false *)
    assert (Hunch := consume_denied_unchanged cfg b now b' H).
    rewrite Hunch. apply refill_tokens_bounded.
Qed.

(* P9: Refill with zero elapsed time and non-negative rate preserves tokens
   (assuming tokens <= max) *)
Theorem refill_zero_elapsed : forall cfg b,
  0 <= rate_per_minute cfg ->
  tokens b <= max_tokens cfg ->
  tokens (refill cfg b (last_refill b)) = tokens b.
Proof.
  intros cfg b Hrate Hmax.
  unfold refill. simpl.
  replace (last_refill b - last_refill b) with 0 by lia.
  replace (0 * rate_per_minute cfg) with 0 by lia.
  replace (tokens b + 0) with (tokens b) by lia.
  case_eq (tokens b <=? max_tokens cfg); intro Hcap.
  - reflexivity.
  - apply Z.leb_gt in Hcap. lia.
Qed.

(* P10: Consecutive refills with non-negative rate are monotone *)
Theorem refill_chain_monotone : forall cfg b t1 t2,
  0 <= rate_per_minute cfg ->
  tokens b <= max_tokens cfg ->
  t1 <= t2 ->
  last_refill b <= t1 ->
  tokens (refill cfg b t1) <= tokens (refill cfg (refill cfg b t1) t2).
Proof.
  intros cfg b t1 t2 Hrate Hmax Ht12 Hbt1.
  apply refill_monotone.
  - unfold refill. simpl. lia.
  - exact Hrate.
  - apply refill_tokens_bounded.
Qed.

End RateLimiter.
