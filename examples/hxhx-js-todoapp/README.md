# hxhx-js-todoapp

A lix-first JS todo app that is compiled through `hxhx --target js`.

This example intentionally combines:

- `coconut.ui` + `coconut.vdom` for the frontend component tree
- Tailwind + shadcn-style design tokens for the UI system
- `tink_web` route annotations + router typing for a tRPC-like typed API surface
- `tink_sql` schema types (`tink.sql.Info`) for SQL DDL + seed insert generation

## Why setup-lix.sh exists

`tink_sql` currently pulls legacy transitive pins that can conflict with the newer
tink stack used by `coconut.ui` and `tink_web`.

`setup-lix.sh` does two things:

1. installs every dependency from GitHub via `lix`
2. links only `tink_sql`'s source path into `deps/tink_sql_src`, while keeping the rest
   of the build on the modern stack

That keeps this example reproducible while still remaining lix-first and GitHub-sourced.

## Run

From repo root:

```bash
npm run test:examples
```

To view the frontend manually:

```bash
cd examples/hxhx-js-todoapp
./setup-lix.sh
"$(bash ../../scripts/hxhx/build-hxhx.sh)" --target js build.hxml --js out/main.js
node -e 'global.window={console:console};global.document={getElementById:function(){return null;}};global.window.document=global.document;global.navigator={};require("./out/main.js")'
python3 -m http.server 4321
# then open http://localhost:4321/public/index.html
```
