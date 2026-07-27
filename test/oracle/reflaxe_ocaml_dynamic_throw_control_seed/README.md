# Dynamic throw-control oracle seed

This fixture freezes what a Haxe user observes when a value statically typed
as `Dynamic` crosses `throw`: exact primitive and class catches use the carried
runtime value, null reaches only the final `Dynamic` catch, and a rethrow keeps
the original value.

The oracle is behavioral only. It is compiled with upstream Haxe 4.3.7 through
the interpreter, JavaScript, and Neko routes. The repository implementation
must satisfy that output through its own MIT-compatible typed control model; no
upstream compiler implementation is copied or translated.

Run:

```bash
npm run test:reflaxe-ocaml:dynamic-throw-oracle
```
