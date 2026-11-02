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
	- `addChar` appends the UTF-8 encoding of a code point through
	  `String.fromCharCode` (see `HxString.fromCharCode`).
	- `length` counts code points, like `String.length`. `Buffer.length` counts
	  bytes, so the buffer keeps its own code-point count: each append adds the
	  length of the appended String, which costs no more than copying it.
	- `toString` returns `Buffer.contents`, a fresh copy. Never expose the
	  buffer's bytes as a String (for example with `Bytes.unsafe_to_string` in
	  `untyped __ocaml__`): the String runtime caches facts about a String by
	  its identity and assumes it never changes after first use.
**/
class StringBuf {
	final buf:ocaml.Buffer;
	var characters:Int;

	public var length(get, never):Int;

	public function new() {
		buf = ocaml.Buffer.create(16);
		characters = 0;
	}

	function get_length():Int {
		return characters;
	}

	function append(s:String):Void {
		ocaml.Buffer.addString(buf, s);
		characters = characters + s.length;
	}

	public function add<T>(x:T):Void {
		append(Std.string(x));
	}

	public function addChar(c:Int):Void {
		append(String.fromCharCode(c));
	}

	public function addSub(s:String, pos:Int, ?len:Int):Void {
		append(len == null ? s.substr(pos) : s.substr(pos, len));
	}

	public function toString():String {
		return ocaml.Buffer.contents(buf);
	}
}
