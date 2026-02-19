/**
	OCaml target override for `EReg`.

	## Why this exists
	Upstream Haxe declares `EReg` as a cross-target API surface but leaves the
	implementation to each target. The default fallback throws a
	`NotImplementedException`, which makes `EReg` unusable for real projects and
	for compiler bootstrapping workloads.

	## What it is
	This file is a **signature-only** extern surface. The actual implementation
	is provided by `std/runtime/EReg.ml`, which is copied into the generated
	output when targeting OCaml.

	## How it maps to OCaml
	- `EReg` is implemented as an OCaml module `EReg` with a type `EReg.t`.
	- The Haxe constructor becomes `EReg.create(pattern, options)`.
	- Instance methods are compiled as module functions which take `self` as the
	  first argument.
	- Because `match` is an OCaml keyword, the backend emits it as `hx_match`
	  (see `CompilationContext.scopedValueName`).

	## Compatibility notes
	The runtime implementation uses OCaml's `Str` library with a best-effort
	translation layer from Haxe's common regex syntax. It is intentionally not a
	full PCRE engine. See `docs/02-user-guide/EREG_STRATEGY.md` for details and
	known limitations.
**/
extern class EReg {
	public function new(r:String, opt:String):Void;

	public function match(s:String):Bool;
	public function matched(n:Int):String;
	public function matchedLeft():String;
	public function matchedRight():String;
	public function matchedPos():{pos:Int, len:Int};
	public function matchSub(s:String, pos:Int, len:Int = -1):Bool;

	public function split(s:String):Array<String>;
	public function replace(s:String, by:String):String;
	public function map(s:String, f:EReg->String):String;

	public static function escape(s:String):String;
}
