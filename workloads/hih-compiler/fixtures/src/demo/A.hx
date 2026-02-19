package demo;

import demo.Util;
import demo.Point;

class A {
	static function main() {}

	// Acceptance fixture for Stage 3 typer:
	// - no return type hint (must infer `String`)
	static function greet() {
		if (true) {
			return "hello";
		} else {
			return "nope";
		}
	}

	// Acceptance fixture for Stage 3 local scope:
	// - infer return type via identifier resolution (`s : String`)
	static function echo(s:String)
		return s;

	// Acceptance fixture: infer `Int` literal return.
	static function fortyTwo() {
		var x = 41;
		x = x + 1;
		if (x == 42) {
			return x;
		}
		return 0;
	}

	// Acceptance fixture: infer `Bool` literal return.
	static function flag()
		return !false;

	// Acceptance fixture for Stage 3 return expression parsing + emission:
	// - return a simple field/call chain captured from the native frontend protocol
	static function callPing():Void
		return Util.ping();

	// Stage 3.3 typing fixture:
	// - imported static call (`Util.makePoint`)
	// - local var type inference from call return
	// - instance method call on a typed local (`p.getX()`)
	static function pointFromUtil():Int {
		var p = Util.makePoint(3);
		return p.getX();
	}
}
