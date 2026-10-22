package backend.cpp;

/**
	Preserve a typed Float constant's bits instead of formatting it as decimal text.
	Literal-only unary signs are resolved here, including negative zero. Ordinary
	arithmetic, Math constants, conversions, and input parsing keep their owners.
 */
function value(expression:HxExpr):Null<Float> {
	return switch expression {
		case EFloat(number): number;
		case EParenthesized(inner, _): value(inner);
		case EUnop(Negate, Prefix, inner):
			final number = value(inner);
			number == null ? null : -number;
		case _: null;
	};
}

/** Native code only copies the representation chosen by the Haxe-authored compiler. */
function boxed(number:Float):String {
	final bits = haxe.io.FPHelper.doubleToI64(number);
	final hex = StringTools.hex(bits.high, 8) + StringTools.hex(bits.low, 8);
	return "hxhx::managed::Value::floatingBits(UINT64_C(0x" + hex + "))";
}
