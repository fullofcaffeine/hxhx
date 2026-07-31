# Inline Dynamic carrier oracle seed

This source records Haxe 4.3.7 behavior when a concrete value enters an inline
function through a `Dynamic` parameter.

Each value is observed by an ordinary Haxe function, `Std.string`, and—on the
OCaml target—a typed runtime function. All three consumers must see the same
value. The upstream JavaScript, Neko, and Python routes use `Std.string` for
the third observation because the native OCaml runtime is not part of the
language oracle.

Primitive (including Float), null, and class text agrees across those upstream routes. Anonymous
structure text is deliberately recorded per target: Haxe 4.3.7 preserves the
value but does not impose one cross-target punctuation or whitespace format.
The portable OCaml fixture therefore owns a separate deterministic
`expected.stdout`; it does not pretend that its anonymous-value spelling is a
language-wide Haxe contract.

This is behavior-oracle evidence only. The hxhx/reflaxe.ocaml implementation
must remain clean-room and may not copy upstream compiler code.
