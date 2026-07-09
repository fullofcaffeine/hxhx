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
#if macro
/**
	Macro-host surface for `Math`.

	Why this exists
	- This repository overrides the upstream `Math` extern so the **OCaml output**
	  can map Haxe’s uppercase constants (`PI`, `NaN`, ...) onto valid OCaml value
	  identifiers (lowercase).
	- Macro code, however, executes on the **host** runtime (eval/neko/hl), where
	  those constants exist under their original names. Applying the OCaml
	  `@:native(...)` renames in macro context would break macro execution.

	What this does
	- Provides an upstream-compatible extern signature for macro execution.
	- Keeps the OCaml-specific renames behind `#if !macro`.
**/
@:pure
extern class Math {
	static var PI(default, null):Float;
	static var NEGATIVE_INFINITY(default, null):Float;
	static var POSITIVE_INFINITY(default, null):Float;
	static var NaN(default, null):Float;
#else
@:pure
extern class Math {
	@:native("pi") static var PI(default, null):Float;
	@:native("negative_infinity") static var NEGATIVE_INFINITY(default, null):Float;
	@:native("positive_infinity") static var POSITIVE_INFINITY(default, null):Float;
	@:native("nan") static var NaN(default, null):Float;
#end

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

/**
	Returns `floor(v)` as a `Float`.

	Why
	- Upstream `Math.ffloor` exists as either an extern (some targets) or a small inline wrapper.
	- On OCaml, keeping it as an extern avoids relying on implicit Int→Float coercions during
	  bootstrapping, which can surface as OCaml type errors when inlined into complex code.
**/
static function ffloor(v:Float):Float;

/** Returns `ceil(v)` as a `Float`. */
static function fceil(v:Float):Float;

/**
	Rounds `v` to float32 precision as a `Float`.

	Note: currently implemented as an identity in the OCaml runtime (double precision),
	which matches Haxe’s “best-effort” semantics on targets without native float32.
**/
static function fround(v:Float):Float;

static function isFinite(f:Float):Bool;
static function isNaN(f:Float):Bool;
}
