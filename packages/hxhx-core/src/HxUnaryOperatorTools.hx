/** Shared rendering and validation helpers for `HxUnaryOperator`. **/
class HxUnaryOperatorTools {
	/** Return the exact Haxe source token represented by `op`. **/
	public static function sourceToken(op:HxUnaryOperator):String {
		return switch (op) {
			case Increment: "++";
			case Decrement: "--";
			case Negate: "-";
			case LogicalNot: "!";
			case BitwiseNot: "~";
		};
	}

	/** Return the matching public `haxe.macro.Unop` constructor name. **/
	public static function macroConstructor(op:HxUnaryOperator):String {
		return switch (op) {
			case Increment: "OpIncrement";
			case Decrement: "OpDecrement";
			case Negate: "OpNeg";
			case LogicalNot: "OpNot";
			case BitwiseNot: "OpNegBits";
		};
	}

	/** Whether `op` is legal with postfix fixity in Haxe 4.3.7. **/
	public static function supportsPostfix(op:HxUnaryOperator):Bool {
		// Keep this as equality rather than an alternative-pattern switch: the
		// current Reflaxe bootstrap lowering erases enum alternatives to wildcards.
		return op == HxUnaryOperator.Increment || op == HxUnaryOperator.Decrement;
	}

	/**
		Verify that an operator/fixity pair can represent Haxe source syntax.

		Callers use this at syntax/macro boundaries so malformed internal values fail
		before a backend can print an invalid target expression.
	**/
	public static function requireValidFixity(op:HxUnaryOperator, fixity:HxUnaryFixity):Void {
		if (fixity == HxUnaryFixity.Postfix && !supportsPostfix(op))
			throw "invalid postfix unary operator " + sourceToken(op);
	}
}
