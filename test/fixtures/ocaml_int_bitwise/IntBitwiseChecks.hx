/** Observe signed bitwise results and operand order without target-specific code. */
class IntBitwiseChecks {
	static final initialized:Int = 1 << 33;

	static function left():Int {
		Sys.println("left");
		return 6;
	}

	static function right():Int {
		Sys.println("right");
		return 3;
	}

	static function dynamicInput(value:Dynamic):Dynamic
		return value & 255;

	public static function run():Void {
		var __hx_call_argument_0 = 9;
		Sys.println(initialized);
		Sys.println(-1 & 255);
		Sys.println(-2147483648 | 1);
		Sys.println(6 ^ 3);
		Sys.println(1 << 31);
		Sys.println(-8 >> 33);
		Sys.println(-1 >>> 33);
		Sys.println(1 << -1);
		Sys.println((3 & 1) + (8 >>> 1));
		Sys.println(left() ^ right());
		Sys.println(__hx_call_argument_0);
	}
}
