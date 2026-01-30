/**
	OCaml target override for `Array`.

	This file defines a portable, stdlib-first surface for `Array<T>`:
	- It keeps the familiar Haxe `Array` API available to user code.
	- The OCaml backend lowers supported operations to `HxArray` runtime helpers
	  for consistent semantics and good performance.

	Notes
	- Some methods are declared `extern` even if the upstream stdlib provides an
	  `inline` implementation. This avoids depending on desugarings that are still
	  evolving in this compiler (e.g. comprehensions and iterator lowering).
	- Unsupported operations currently fail with a compile-time guardrail error
	  during code generation.
**/

import haxe.iterators.ArrayKeyValueIterator;

extern class Array<T> {
	public var length(default, null):Int;

	public function new():Void;

	public function concat(a:Array<T>):Array<T>;
	public function join(sep:String):String;

	public function pop():Null<T>;
	public function push(x:T):Int;
	public function reverse():Void;
	public function shift():Null<T>;
	public function slice(pos:Int, ?end:Int):Array<T>;
	public function sort(f:T->T->Int):Void;
	public function splice(pos:Int, len:Int):Array<T>;
	public function unshift(x:T):Void;
	public function insert(pos:Int, x:T):Void;
	public function remove(x:T):Bool;

	public function contains(x:T):Bool;
	public function indexOf(x:T, ?fromIndex:Int):Int;
	public function lastIndexOf(x:T, ?fromIndex:Int):Int;

	public function copy():Array<T>;

	@:runtime public inline function iterator():haxe.iterators.ArrayIterator<T> {
		return new haxe.iterators.ArrayIterator(this);
	}

	@:pure @:runtime public inline function keyValueIterator():ArrayKeyValueIterator<T> {
		return new ArrayKeyValueIterator(this);
	}

	/**
		Map and filter are declared `extern` so the OCaml backend can lower them
		directly to runtime helpers, avoiding array-comprehension desugarings.
	**/
	public function map<S>(f:T->S):Array<S>;
	public function filter(f:T->Bool):Array<T>;

	public function resize(len:Int):Void;
}

