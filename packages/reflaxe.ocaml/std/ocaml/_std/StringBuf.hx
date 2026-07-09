/**
	OCaml target override for `StringBuf`.

	Why this exists
	- The upstream `StringBuf` implementation is heavily `inline`. That is great for
	  most targets, but early milestones of this backend intentionally do not
	  implement every inlined lowering pattern (notably all compound assignment
	  shapes).
	- Some upstream stdlib code (e.g. `haxe.CallStack`) relies on `StringBuf` to
	  build strings, and those modules are compiled under `-warn-error`, so even
	  “harmless” partial stubs can break the build.

	What this file does
	- Provides a small, non-`inline` implementation of `StringBuf` so callsites
	  lower to real method calls instead of inlined field mutation.
	- Keeps the public API consistent with the upstream stdlib.

	How it maps to OCaml
	- We store the accumulated buffer in an OCaml `Stdlib.Buffer.t`.
	- `add*` methods call `Stdlib.Buffer.add_*` so repeated appends are efficient
	  (amortized), avoiding O(n^2) string concatenation patterns.

	Notes / tradeoffs
	- This is a **portable surface**: we preserve Haxe `StringBuf` behavior, but the
	  underlying implementation is OCaml-specific and intentionally optimized.
	- `addChar` uses `String.fromCharCode` semantics, which (in this backend) are
	  currently best-effort for codepoints 0..255 (see `HxString.fromCharCode`).
**/
class StringBuf {
	final buf:ocaml.Buffer;

	public var length(get, never):Int;

	public function new() {
		buf = ocaml.Buffer.create(16);
	}

	function get_length():Int {
		return ocaml.Buffer.length(buf);
	}

	public function add<T>(x:T):Void {
		ocaml.Buffer.addString(buf, Std.string(x));
	}

	public function addChar(c:Int):Void {
		ocaml.Buffer.addString(buf, String.fromCharCode(c));
	}

	public function addSub(s:String, pos:Int, ?len:Int):Void {
		ocaml.Buffer.addString(buf, len == null ? s.substr(pos) : s.substr(pos, len));
	}

	public function toString():String {
		return ocaml.Buffer.contents(buf);
	}
}
