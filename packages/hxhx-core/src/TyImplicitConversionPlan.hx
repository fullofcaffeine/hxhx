/**
	Records one type conversion chosen by the shared Haxe typer before backend code
	generation.

	For example, `NullFloat += NullFloat` may use an operator whose right argument
	is `Float`. Haxe accepts that argument only when `NullFloat` declares a `to`
	conversion compatible with `Float`; the compound result can be stored back only
	when the abstract also declares a compatible `from` conversion. This plan keeps
	those two decisions explicit so target backends receive casts instead of
	repeating abstract-conversion lookup.

	The current bounded model supports exact types, `Int` to `Float`, `Dynamic`,
	and one compatible conversion declared directly in an abstract header.
	Unsupported routes, or multiple different compatible declarations on the same
	side, remain inapplicable rather than being guessed from the type used by a
	target language to store the value.
**/
class TyImplicitConversionPlan {
	static inline final EXACT = "exact";
	static inline final NUMERIC_WIDENING = "numeric-widening";
	static inline final DYNAMIC = "dynamic";
	static inline final ABSTRACT_TO = "abstract-to";
	static inline final ABSTRACT_FROM = "abstract-from";

	final kind:String;
	final actualType:TyType;
	final expectedType:TyType;
	final viaType:Null<TyType>;
	final score:Int;

	function new(kind:String, actualType:TyType, expectedType:TyType, viaType:Null<TyType>, score:Int) {
		this.kind = kind;
		this.actualType = actualType;
		this.expectedType = expectedType;
		this.viaType = viaType;
		this.score = score;
	}

	static function nullableCompatible(expected:TyType, actual:TyType):Bool {
		if (expected == null || actual == null)
			return false;
		if (expected.getSemanticKey() == actual.getSemanticKey())
			return true;
		if (expected.isNullable())
			return nullableCompatible(expected.getNullableInner(), actual);
		if (actual.isNullable())
			return nullableCompatible(expected, actual.getNullableInner());
		return false;
	}

	static function uniqueCompatible(types:Array<TyType>, expected:TyType):Null<TyType> {
		var selected:Null<TyType> = null;
		for (type in types) {
			if (!nullableCompatible(expected, type))
				continue;
			if (selected != null && selected.getSemanticKey() != type.getSemanticKey())
				return null;
			selected = type;
		}
		return selected;
	}

	/** Choose one bounded implicit conversion, or return null when none is proven. **/
	public static function select(index:TyperIndex, expected:TyType, actual:TyType):Null<TyImplicitConversionPlan> {
		if (expected == null || actual == null || expected.isUnknown() || actual.isUnknown())
			return null;
		if (expected.getSemanticKey() == actual.getSemanticKey())
			return new TyImplicitConversionPlan(EXACT, actual, expected, null, 4);
		if (expected.getDisplay() == "Float" && actual.getDisplay() == "Int")
			return new TyImplicitConversionPlan(NUMERIC_WIDENING, actual, expected, null, 3);

		final actualIdentity = actual.getNominalIdentity();
		final actualAbstract = actualIdentity == null
			|| index == null ? null : index.getAbstractByFullName(actualIdentity.getCanonicalName());
		if (actualAbstract != null) {
			final via = uniqueCompatible(actualAbstract.getImplicitToTypes(), expected);
			if (via != null)
				return new TyImplicitConversionPlan(ABSTRACT_TO, actual, expected, via, 2);
		}

		final expectedIdentity = expected.getNominalIdentity();
		final expectedAbstract = expectedIdentity == null
			|| index == null ? null : index.getAbstractByFullName(expectedIdentity.getCanonicalName());
		if (expectedAbstract != null) {
			final via = uniqueCompatible(expectedAbstract.getImplicitFromTypes(), actual);
			if (via != null)
				return new TyImplicitConversionPlan(ABSTRACT_FROM, actual, expected, via, 2);
		}

		if (expected.isDynamic())
			return new TyImplicitConversionPlan(DYNAMIC, actual, expected, null, 1);
		return null;
	}

	public function getScore():Int
		return score;

	public function getKind():String
		return kind;

	public function getActualType():TyType
		return actualType;

	public function getExpectedType():TyType
		return expectedType;

	public function getViaType():Null<TyType>
		return viaType;

	/** Whether this plan projects an abstract through a declared `to` type. **/
	public function isAbstractTo():Bool
		return kind == ABSTRACT_TO;

	/**
		Whether this abstract `to` conversion only exposes its existing storage.

		A different destination can require executable conversion logic. The shared
		typed body must not replace that logic with a plain representation cast.
	**/
	public function isRepresentationPreservingAbstractTo(index:TyperIndex):Bool {
		if (!isAbstractTo() || index == null)
			return false;
		final actualIdentity = actualType.getNominalIdentity();
		final abstractInfo = actualIdentity == null ? null : index.getAbstractByFullName(actualIdentity.getCanonicalName());
		return abstractInfo != null && abstractInfo.getUnderlyingType().getSemanticKey() == expectedType.getSemanticKey();
	}

	/** Materialize the already-selected conversion in the shared typed body. **/
	public function apply(expression:TypedExpr):TypedExpr {
		if (kind == EXACT)
			return expression.withType(expectedType);
		return TypedExpr.castValue(expression, expectedType.getDisplay(), expectedType, expression.getPosition());
	}
}
