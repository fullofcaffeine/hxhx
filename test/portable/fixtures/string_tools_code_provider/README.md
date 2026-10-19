# StringTools character codes and EOF

The OCaml provider returns ASCII character codes through typed String operations.
At end-of-string, fastCodeAt returns the native sentinel and isEof recognizes it.
Eval keeps its own sentinel. Callers can use isEof without knowing either value.

This fixture checks valid ASCII codes, empty and exhausted strings, retained
function calls, and argument evaluation order. It calls unsafeCodeAt only at
valid indexes because upstream eval throws on an exhausted string.
The OCaml runtime remains byte-based; this fixture does not establish Unicode parity.

Run the native fixture:

```sh
PORTABLE_FIXTURE_ALLOWLIST=string_tools_code_provider npm run test:portable
```

Compare its fixed output with upstream:

```sh
haxe -cp test/portable/fixtures/string_tools_code_provider/src --run Main
```

The Stage3 exception-provider closure is a separate acceptance test. Passing
this standalone Reflaxe fixture does not prove that closure or promote providers.
