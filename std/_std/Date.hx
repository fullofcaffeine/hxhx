/**
	OCaml target override for `Date`.

	## Why this exists
	The OCaml backend needs a concrete runtime representation for `Date` because:

	- `sys.FileSystem.stat()` returns a `sys.FileStat` structure containing `Date`
	  fields (`atime`, `mtime`, `ctime`).
	- We intentionally avoid relying on reflection-heavy/target-specific `Date`
	  implementations from other Haxe targets.

	## What it is
	This file is a **signature-only** extern surface. The real implementation lives
	in the OCaml runtime module `Date.ml` shipped in `std/runtime/`.

	## How it maps to OCaml
	- `Date` is implemented as an OCaml module `Date` with a type `Date.t`.
	- Instance methods become module functions that take `self` first, followed by
	  arguments, then `()` for zero-arg methods (same style as this backend’s class lowering).
	- Times are represented as **milliseconds since Unix epoch** (Float), matching
	  Haxe’s `Date.getTime()` and `Date.fromTime()`.

	## Limitations
	Only a minimal subset of the full Haxe `Date` API is implemented today. Add
	missing methods as we need them for bootstrapping.
**/
extern class Date {
	/**
		Creates a local-time date from its components.

		`month` is 0-based (0=January), matching Haxe.
	**/
	function new(year:Int, month:Int, day:Int, hour:Int, min:Int, sec:Int);

	/** Returns the current local time. */
	static function now():Date;

	/** Creates a date from a millisecond timestamp (Unix epoch). */
	static function fromTime(t:Float):Date;

	/**
		Creates a Date from the formatted string `s`.

		Accepted formats match upstream Haxe:
		- `"YYYY-MM-DD hh:mm:ss"`
		- `"YYYY-MM-DD"`
		- `"hh:mm:ss"`
	**/
	static function fromString(s:String):Date;

	/** Returns the millisecond timestamp (Unix epoch). */
	function getTime():Float;

	function getHours():Int;
	function getMinutes():Int;
	function getSeconds():Int;
	function getFullYear():Int;
	function getMonth():Int;
	function getDate():Int;
	function getDay():Int;

	function getUTCHours():Int;
	function getUTCMinutes():Int;
	function getUTCSeconds():Int;
	function getUTCFullYear():Int;
	function getUTCMonth():Int;
	function getUTCDate():Int;
	function getUTCDay():Int;

	/**
		Returns the time zone offset of local time relative to UTC, in minutes (UTC - local).
	**/
	function getTimezoneOffset():Int;

	/** Basic human-readable representation (primarily for debugging). */
	function toString():String;
}
