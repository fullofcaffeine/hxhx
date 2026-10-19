# PHP renderer callback boundary

This fixture imports the actual compiler helper from its independent Haxe module.
The helper invokes a callback once and returns its value unchanged. Moving it out
of the emitter dependency cycle preserves its generic result and the existing
exception behavior. The enum hint does not create ambient rendering state.

Native OCaml and upstream Haxe eval must match the expected output for nested
callbacks, empty strings, Int and Bool results, shared arrays and records, and
exceptions. Array and record mutation must remain visible through the original
reference. This does not prove general generic signatures inside recursive modules;
that separate compiler capability remains tracked by `haxe_ocaml-896mh`.

Run from the repository root:

```sh
PATH="$PWD/node_modules/.bin:$PATH" \
  PORTABLE_FIXTURE_ALLOWLIST=php_render_callback \
  bash scripts/test-portable.sh
```

Full compiler bootstrap and PHP enum rendering still require integration checks.
