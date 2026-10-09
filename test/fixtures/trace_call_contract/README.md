# Trace language behavior

These authored programs specify observable Haxe 4.3.7 behavior. Run them through
`haxe test/m14_js_feature_upstream_contract_test.hxml`. The observer compiles and
executes eval, JavaScript and Neko programs, and compares exact output.

- `TraceOrder` changes the logger inside a statement-valued argument. Eval and
  Neko call the original logger; JavaScript calls the replacement after moving
  the argument statements before the call.
- `TraceCallOrder` changes the logger inside an ordinary function-call argument.
  All three targets call the original logger. A target-wide late-lookup rule
  would be incorrect.
- `TracePosition` checks the public class, method, source-line and extra-argument
  information passed to an overridden logger.
- `TraceShadow` shows that a same-named local does not shadow bare `trace` in the
  pinned baseline. With `no-traces`, trace operand effects also disappear.

- `TraceDisabled` proves that disabled bare traces do not type or execute their
  operands. Qualified methods, parenthesized local calls, and empty local calls
  named `trace` still execute. Run `haxe test/m14_trace_disabled_test.hxml` for
  the matching hxhx JavaScript and Neko runtime regression.

The upstream observer defines the expected behavior. The local runtime check
proves the disabled-trace case only. `M14DynamicGenericCallTest` retains the
local failure for
`trace(fixed(block, block))`. Task `haxe_ocaml-hgtz2` owns the shared typed trace
contract and its implementation. Do not remove that failure or bypass unresolved
operand checks to make this upstream observer pass.
