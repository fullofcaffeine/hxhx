# Stage3 `Std.int` of out-of-range Floats

```haxe
Std.int(4294967295.0);   // upstream eval: -1; native was 4294967295
Std.int(2147483648.0);   // upstream eval: -2147483648; native was 2147483648
```

Upstream Haxe 4.3.7 eval (the reference target) truncates toward zero and
then wraps the result modulo 2^32 into a signed 32-bit Int. Native `Std.int`
(the runtime `Std.ml`) used OCaml's `int_of_float` alone, which returns a
63-bit value, so a result outside the Int range leaked into later Int
arithmetic and printing. `Std.int` now truncates and then wraps:
`Int32.to_int (Int32.of_int (int_of_float x))`.

`Main.hx` covers NaN, `±0.5`, `±1.9`, `-0.0`, the values around `±2^31` and
`2^32`, `±3e9`, `±1e10`, `2^53`, Int arithmetic on a wrapped result, and
`Std.int` of a `UInt` above `0x7FFFFFFF`.
`npm run test:m14:stage3-std-int-wrap` checks that upstream eval prints
`expected.stdout`, then requires the Stage3 native executable to print the
same text.

## Target differences (known_divergence)

Out-of-range `Std.int` is not stable across upstream targets. This change
was reviewed under the gate in `docs/00-project/FLOAT_NUMERIC_REVIEW_GATE.md`;
the gate answers are recorded on Bead `haxe_ocaml-3lpr4`. Observed with
Haxe 4.3.7 on an arm64 macOS host:

| Input | eval | neko | python |
|---|---|---|---|
| `nan` | 0 | 0 | null |
| `+inf` | -1 | 2147483647 | null |
| `-inf` | 0 | -2147483648 | null |
| `0.5` | 0 | 0 | 0 |
| `-0.5` | 0 | 0 | 0 |
| `1.9` | 1 | 1 | 1 |
| `-1.9` | -1 | -1 | -1 |
| `-0.0` | 0 | 0 | 0 |
| `2^31-1` | 2147483647 | 2147483647 | 2147483647 |
| `2^31` | -2147483648 | 2147483647 | 2147483648 |
| `2^31+0.5` | -2147483648 | 2147483647 | 2147483648 |
| `-2^31` | -2147483648 | -2147483648 | -2147483648 |
| `-2^31-1` | 2147483647 | -2147483648 | -2147483649 |
| `2^32-1` | -1 | 2147483647 | 4294967295 |
| `2^32` | 0 | 2147483647 | 4294967296 |
| `2^32+1` | 1 | 2147483647 | 4294967297 |
| `3e9+0.5` | -1294967296 | 2147483647 | 3000000000 |
| `-3e9-0.5` | 1294967296 | -2147483648 | -3000000000 |
| `1e10` | 1410065408 | 2147483647 | 10000000000 |
| `-1e10` | -1410065408 | -2147483648 | -10000000000 |
| `2^53` | 0 | 2147483647 | 9007199254740992 |
| `1e20` | -1 | 2147483647 | 100000000000000000000 |
| `-1e20` | 0 | -2147483648 | -100000000000000000000 |
| `1e300` | -1 | 2147483647 | 100000000000… |
| `Std.int(2^32-1) + 1` | 0 | -2147483648 | 4294967296 |

hxcpp and HashLink were not installed on the host. Both use a C `(int)`
cast, which is undefined for out-of-range values. JS uses `x | 0`
(ToInt32), which wraps modulo 2^32 for every finite double. That agrees
with eval wherever eval itself is host-independent (|x| < 2^63).

For `±Infinity` and `|x| >= 2^63`, eval's result comes from the CPU's
float-to-int conversion: arm64 saturates, and x86-64 yields
`0x8000000000000000`. Native uses the same OCaml primitive followed by the
same wrap, so it matches eval on the same host. The fixture does not pin
these values.

Not changed: the reflaxe.ocaml backend inlines `Std.int(x)` as
`int_of_float` and skips the runtime (Bead `haxe_ocaml-kmdfe`). Native
`Math.floor`, `Math.ceil`, and `Math.round`, including the Stage3
`Math.round` intrinsic, also use `int_of_float` directly (Bead haxe_ocaml-32vsc).
