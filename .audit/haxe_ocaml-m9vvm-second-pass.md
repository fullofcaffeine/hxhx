# Second-pass review: early-return fixture policy

## Outcome

The correction is test-only and restores the fixture's ability to check current
supported behavior. It does not change Haxe lowering, OCaml generation, runtime
code, report data, or a public readiness claim.

## Checks performed

- `OcamlStdioInput.readBytes` must have one admitted throw occurrence and one
  decision, with no blockers. The decision is tied to the exact function and
  `Stdio.hx` source owner.
- The throw remains on the compiler-owned Haxe exception channel, uses the
  existing typed-signal capability, carries only the `Dynamic` static tag, and
  is eligible in both portable and metal profiles.
- The payload and whole-program representation agree on semantic type,
  `Haxe_io_Eof.t` carrier, representation ID/revision, nullable nominal boxing,
  layout revision, and representation proof. This prevents a loose
  `status === admitted` check from accepting a different exception model.
- `OcamlStdioOutput.writeBytes` must still report that no throw is needed. The
  Eof update therefore cannot launder an unrelated output-method throw.
- The null-string assertion still requires the canonical `HxString` sentinel to
  enter `Obj.repr` and a typed `string` to leave `Obj.obj`. It accepts only the
  two OCaml spellings that differ by redundant parentheses; it does not accept a
  different value or recovery type.
- The three-route nominal-throw oracle remains the independent behavior source.
  The complete early-return fixture then generates, builds, runs, repeats the
  report, and rejects its full invalid-report matrix.

No remaining blocker or claim expansion was found.
