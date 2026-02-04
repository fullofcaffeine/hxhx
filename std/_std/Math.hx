/**
	OCaml target override for `Math`.

	## Why this exists
	Upstream Haxe defines `Math` as an `extern` class whose implementation is
	provided by each target runtime. Without an OCaml runtime implementation,
	any reference to `Math.*` either fails at link time (missing module) or
	produces invalid OCaml identifiers (notably `Math.PI`).

	## What it is
	This file is a **signature-only** extern surface. The actual implementation
	is provided by `std/runtime/Math.ml`.

	## How it maps to OCaml
	- `Math` is implemented as an OCaml module `Math`.
	- Uppercase constant names in Haxe (`PI`, `NaN`, ...) are not valid OCaml
	  value identifiers, so we map them via `@:native` to lowercase OCaml names
	  (`pi`, `nan`, ...).
**/
@:pure
extern class Math {
	@:native("pi") static var PI(default, null):Float;
	@:native("negative_infinity") static var NEGATIVE_INFINITY(default, null):Float;
	@:native("positive_infinity") static var POSITIVE_INFINITY(default, null):Float;
	@:native("nan") static var NaN(default, null):Float;

	static function abs(v:Float):Float;
	static function min(a:Float, b:Float):Float;
	static function max(a:Float, b:Float):Float;

	static function sin(v:Float):Float;
	static function cos(v:Float):Float;
	static function tan(v:Float):Float;
	static function asin(v:Float):Float;
	static function acos(v:Float):Float;
	static function atan(v:Float):Float;
	static function atan2(y:Float, x:Float):Float;
	static function exp(v:Float):Float;
	static function log(v:Float):Float;
	static function pow(v:Float, exp:Float):Float;
	static function sqrt(v:Float):Float;

	static function round(v:Float):Int;
	static function floor(v:Float):Int;
	static function ceil(v:Float):Int;
	static function random():Float;

	static inline function ffloor(v:Float):Float return floor(v);
	static inline function fceil(v:Float):Float return ceil(v);
	static inline function fround(v:Float):Float return round(v);

	static function isFinite(f:Float):Bool;
	static function isNaN(f:Float):Bool;
}

