(lang dune 3.21)
(name clawq)
(using coq 0.8)
(warnings (deprecated_coq_lang disabled))

(package
 (name clawq)
 (synopsis "Coq port scaffold of nullclaw")
 (description "Coq-first assistant runtime with OCaml extraction pipeline")
 (depends
  dune
  coq
  ocaml
  cmdliner
  yojson
  sqlite3
  lwt
  cohttp-lwt-unix
  tls-lwt
  logs
  fmt
  (alcotest :with-test)))
