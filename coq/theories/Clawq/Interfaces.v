From Coq Require Import String List.
Import ListNotations.
Open Scope string_scope.

Record Provider := {
  provider_name : string;
  provider_complete : string -> string;
  provider_health : string
}.

Record Channel := {
  channel_name : string;
  channel_start : unit -> bool;
  channel_stop : unit -> bool;
  channel_send : string -> bool
}.

Record Tool := {
  tool_name : string;
  tool_invoke : list string -> string;
  tool_risk_level : string
}.

Record Memory := {
  memory_store : string -> string -> bool;
  memory_recall : string -> option string;
  memory_forget : string -> bool
}.

Record RuntimeAdapter := {
  runtime_name : string;
  runtime_start : unit -> bool;
  runtime_stop : unit -> bool
}.

Record Tunnel := {
  tunnel_name : string;
  tunnel_start : unit -> bool;
  tunnel_status : string
}.

Record Security := {
  security_workspace_only : bool;
  security_audit_enabled : bool;
  security_encrypt_secrets : bool
}.
