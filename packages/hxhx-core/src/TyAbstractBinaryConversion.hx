/** Evidence for one operand or compound-result conversion, including executable abstract methods. */
private enum BinaryConversionEvidence {
	Implicit(plan:TyImplicitConversionPlan);
	Method(plan:TyAbstractMethodConversion, result:TyImplicitConversionPlan);
}

/**
	Retain the conversion selected while checking an abstract binary declaration.
	Header conversions precede executable methods. Method calls remain typed calls,
	so lowering can evaluate them with their source operand before the next operand.
	This composition does not add recursive method lookup to the header selector.
 */
class TyAbstractBinaryConversion {
	final expected:TyType;
	final evidence:BinaryConversionEvidence;

	function new(expected:TyType, evidence:BinaryConversionEvidence) {
		this.expected = expected;
		this.evidence = evidence;
	}

	public static function select(index:TyperIndex, expected:TyType, actual:TyType):Null<TyAbstractBinaryConversion> {
		final implicit = TyImplicitConversionPlan.select(index, expected, actual);
		if (implicit != null)
			return new TyAbstractBinaryConversion(expected, Implicit(implicit));
		final method = TyAbstractMethodConversion.select(index, expected, actual);
		if (method == null)
			return null;
		final result = TyImplicitConversionPlan.select(index, expected, method.getResultType());
		return result == null ? null : new TyAbstractBinaryConversion(expected, Method(method, result));
	}

	/** Scores choose argument orientation within one declaration, never priority between declarations. */
	public function getScore():Int
		return switch evidence {
			case Implicit(plan): plan.getScore();
			case Method(_, _): 2;
		};

	public function getExpectedType():TyType
		return expected;

	/** Existing plans validate the exact source type before publishing a cast or method call. */
	public function apply(expression:TypedExpr):TypedExpr
		return switch evidence {
			case Implicit(plan): plan.apply(expression);
			case Method(plan, result): result.apply(plan.apply(expression));
		};
}
