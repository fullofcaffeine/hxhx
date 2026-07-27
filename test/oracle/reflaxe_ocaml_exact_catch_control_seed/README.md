# Exact primitive catch-control oracle seed

This fixture records observable catch ordering and payload behavior from
upstream Haxe 4.3.7. It is compiled independently through the interpreter,
JavaScript, and Neko. A separate invalid input also proves that upstream rejects
any source catch after `Dynamic`. These results guide the clean-room OCaml
control plan but provide no implementation code.

Run it with:

```bash
npm run test:reflaxe-ocaml:exact-catch-oracle
```
