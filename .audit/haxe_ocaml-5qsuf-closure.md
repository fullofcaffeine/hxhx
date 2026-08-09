Complete numeric literals are protected across both maintained bootstrap
compiler forms.

The focused fixture uses upstream Haxe 4.3.7 plus a reviewed expected output as
an independent oracle. It covers the exact integer and long-decimal values that
previously lost digits, together with hexadecimal, negative, boundary,
separator, leading-dot, and exponent forms. Each candidate's generated
JavaScript is inspected, executed, and produced twice identically.

The stage0-free snapshot route passes on current main. The current-source route
passed at f09500606 after a full Haxe/Reflaxe generation and 1,434-action Dune
build. No hxhx compiler source, fixture, or fixture-runner file changed between
that current-source candidate and closure, so it remains the exact current
numeric-literal input; later code only changed reflaxe.ocaml report identities.

The general behavior regression replaces dependence on private DateTools and
FPHelper field names while directly covering their formerly truncated values.
No compiler fallback or output repair was added.

README Goals and readiness percentages remain unchanged. This closes one
bootstrap correctness regression, not Full1, shared-target, or release
readiness.
