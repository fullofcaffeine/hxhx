package demo;

import demo.Point;

class Util {
	public static function ping() {}

	public static function isNan0():Bool
		return Math.isNaN(0.0);

	/**
		Stage 3.3 typing fixture: imported static call + `new`.

		Why
		- We want `A.pointFromUtil()` to type-check `Util.makePoint(3)` and infer the
		  local variable type as `demo.Point` from the static method signature.

		What
		- Returns a new `demo.Point`.
	**/
	public static function makePoint(x:Int):demo.Point
		return new Point(x);
}
