From Coq Require Import Extraction.
From Coq Require Import ExtrOcamlBasic.
From Coq Require Import ExtrOcamlNativeString.
From Coq Require Import ExtrOcamlNatInt.
Require Import Clawq.Cli.
Require Import Clawq.Config.

Extraction Language OCaml.
Extraction "src/extracted/clawq_core.ml"
  Clawq.Cli.parse_command
  Clawq.Cli.dispatch
  Clawq.Config.validate_config
  Clawq.Config.valid_weights
  Clawq.Config.default_config.
