class Main {
	static final DECIMALS = [31, 28, -31, 1_234_567, 2147483647, -2147483648];
	static final HEXADECIMALS = [0x1f, 0x7fffffff];
	static final FLOATS = [0.69314718056, 1e-5, 3.14e+2, .5, -.125, 1E10, 0.693_147_180_56];

	static function main():Void {
		trace("HXHX_NUMERIC_LITERALS:" + DECIMALS.join(",") + "|" + HEXADECIMALS.join(",") + "|" + FLOATS.join(","));
	}
}
