/** Body operations constrain omitted inputs while written and unused inputs stay distinct. */
class Main {
	static function bitsAnd(left, right)
		return left & right;

	static function bitsOr(left, right)
		return left | right;

	static function bitsXor(left, right)
		return left ^ right;

	static function shiftLeft(value, count)
		return value << count;

	static function shiftRight(value, count)
		return value >> count;

	static function shiftUnsigned(value, count)
		return value >>> count;

	static function dynamicPeer(value, other:Dynamic)
		return value & other;

	static function explicit(value:Dynamic)
		return value & 1;

	static function alias(value) {
		var copy = value;
		return copy & 255;
	}

	static function unused(value):Void {}

	static function main():Void {}
}
