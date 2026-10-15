/** Integer operators preserve 32-bit patterns and evaluate each operand once. */
class Main {
	static var order:Int = 0;

	static function operand(value:Int, marker:Int):Int {
		order = order * 10 + marker;
		return value;
	}

	static function check(value:Int, count:Int, left:Int, signed:Int, unsigned:Int):Void {
		if ((value << count) != left || (value >> count) != signed || (value >>> count) != unsigned)
			throw "integer shift changed its 32-bit result";
	}

	static function bits(left:Int, right:Int, andValue:Int, orValue:Int, xorValue:Int):Void {
		if ((left & right) != andValue || (left | right) != orValue || (left ^ right) != xorValue)
			throw "integer bitwise operation changed its 32-bit result";
	}

	public static function common():Void {
		compound();
		check(-1, 0, -1, -1, -1);
		check(-1, 1, -2, -1, 2147483647);
		check(-1, 16, -65536, -1, 65535);
		check(-1, 31, -2147483647 - 1, -1, 1);
		check(-2147483647 - 1, 1, 0, -1073741824, 1073741824);
		check(2147483647, 1, -2, 1073741823, 1073741823);
		check(1, 31, -2147483647 - 1, 0, 0);
		check(-1, 32, -1, -1, -1);
		check(-1, 33, -2, -1, 2147483647);
		check(-1, -1, -2147483647 - 1, -1, 1);
		check(-2147483647 - 1, 32, -2147483647 - 1, -2147483647 - 1, -2147483647 - 1);
		check(1, -2147483647 - 1, 1, 1, 1);
		check(1, 2147483647, -2147483647 - 1, 0, 0);
		bits(5, 3, 1, 7, 6);
		bits(-1, 0, 0, -1, -1);
		bits(-2147483647 - 1, -1, -2147483647 - 1, -1, 2147483647);
		if ((operand(-8, 1) >> operand(2, 2)) != -2 || order != 12)
			throw "shift operands did not execute once in order";
		order = 0;
		if ((operand(5, 1) ^ operand(3, 2)) != 6 || order != 12)
			throw "bitwise operands did not execute once in order";
	}

	/** Compound operators return the stored result and read their target before RHS effects. */
	static function compound():Void {
		var value = 63;
		if ((value &= 10) != 10 || value != 10)
			throw "and assignment lost its result";
		value |= 32;
		if (value != 42)
			throw "or assignment changed its result";
		value ^= 15;
		if (value != 37)
			throw "xor assignment changed its result";
		value <<= 1;
		if (value != 74)
			throw "left shift assignment changed its result";
		value >>= 1;
		if (value != 37)
			throw "signed shift assignment changed its result";
		value = -1;
		if ((value >>>= 1) != 2147483647 || value != 2147483647)
			throw "unsigned shift assignment lost its result";
		value = -8;
		if ((value >>= 33) != -4 || value != -4)
			throw "compound shift count was not masked";
		var captured = 15;
		final rhs = () -> {
			captured = 0;
			return 3;
		};
		if ((captured &= rhs()) != 3 || captured != 3)
			throw "compound capture read occurred after RHS effects";
	}

	/** Native nullable operands use zero for numeric operations and retain their original storage. */
	static function nullableBits(left:Null<Int>, right:Null<Int>, andValue:Int, orValue:Int, xorValue:Int):Void {
		final leftWasNull = left == null;
		final rightWasNull = right == null;
		if ((left & right) != andValue || (left | right) != orValue || (left ^ right) != xorValue)
			throw "nullable bit operation changed its numeric conversion";
		if ((left == null) != leftWasNull || (right == null) != rightWasNull)
			throw "nullable bit operation changed its source";
	}

	static function nullableShift(value:Null<Int>, count:Null<Int>, left:Int, signed:Int, unsigned:Int):Void {
		if ((value << count) != left || (value >> count) != signed || (value >>> count) != unsigned)
			throw "nullable shift changed its numeric conversion";
	}

	static function main():Void {
		common();
		nullableBits(null, 1, 0, 1, 1);
		nullableBits(-8, null, 0, -8, -8);
		nullableBits(null, null, 0, 0, 0);
		nullableBits(5, 3, 1, 7, 6);
		nullableShift(null, 1, 0, 0, 0);
		nullableShift(-8, null, -8, -8, -8);
		nullableShift(null, null, 0, 0, 0);
		nullableShift(-8, 1, -16, -4, 2147483644);
	}
}
