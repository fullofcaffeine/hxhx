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
	final backingType:Null<TyType>;
	final coreTypeCast:Bool;

	function new(kind:String, actualType:TyType, expectedType:TyType, viaType:Null<TyType>, score:Int, ?backingType:TyType, coreTypeCast:Bool = false) {
		this.kind = kind;
		this.actualType = actualType;
		this.expectedType = expectedType;
		this.viaType = viaType;
		this.score = score;
		this.backingType = backingType;
		this.coreTypeCast = coreTypeCast;
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

	/** A declared Dynamic input is a fallback; it must not hide conflicting specific conversions. */
	static function uniqueCompatible(types:Array<TyType>, expected:TyType, allowDynamicInput:Bool = false):Null<TyType> {
		var selected:Null<TyType> = null;
		var dynamicInput:Null<TyType> = null;
		for (type in types) {
			if (allowDynamicInput && type.isDynamic())
				dynamicInput = type;
			if (!nullableCompatible(expected, type))
				continue;
			if (selected != null && selected.getSemanticKey() != type.getSemanticKey())
				return null;
			selected = type;
		}
		return selected == null ? dynamicInput : selected;
	}

	/** Applied arguments bind exact declaration parameters before header or storage comparison. */
	static function abstractBindings(info:Null<TyAbstractInfo>, applied:TyType):Null<haxe.ds.StringMap<TyType>> {
		if (info == null || info.getTypeParameterIds().length != applied.getTypeArguments().length)
			return null;
		return TyTypeSubstitution.bind(info.getTypeParameterIds(), applied.getTypeArguments(), info.getIdentity().getCanonicalName());
	}

	static inline final MAX_FROM_CHAIN = 3;

	/**
		A `from` type that is itself an abstract may accept the value through its own `from` types:
		`EitherType<A, EitherType<B, C>>` accepts a B (haxe_ocaml-c6wur). Haxe 4.3.7's do_check_cast
		recurses into each `from` type of the destination (abstractCast.ml). Only a chain whose every
		step keeps the storage is accepted here, so the single cast the outer plan emits is exact.
		Exactly one `from` type may accept the value.
	**/
	static function nestedFrom(index:TyperIndex, fromTypes:Array<TyType>, actual:TyType, depth:Int):Null<TyType> {
		var selected:Null<TyType> = null;
		for (type in fromTypes) {
			final identity = type.getNominalIdentity();
			if (identity == null || index == null || index.getAbstractByFullName(identity.getCanonicalName()) == null)
				continue;
			final inner = select(index, type, actual, depth + 1);
			if (inner == null || !(inner.kind == EXACT || inner.isRepresentationPreservingAbstractConversion()))
				continue;
			if (selected != null && selected.getSemanticKey() != type.getSemanticKey())
				return null;
			selected = type;
		}
		return selected;
	}

	/** Choose one bounded implicit conversion, or return null when none is proven. **/
	public static function select(index:TyperIndex, expected:TyType, actual:TyType, depth:Int = 0):Null<TyImplicitConversionPlan> {
		if (expected == null || actual == null || expected.isUnknown() || actual.isUnknown())
			return null;
		if (expected.getSemanticKey() == actual.getSemanticKey())
			return new TyImplicitConversionPlan(EXACT, actual, expected, null, 4);
		if (expected.getDisplay() == "Float" && actual.getDisplay() == "Int")
			return new TyImplicitConversionPlan(NUMERIC_WIDENING, actual, expected, null, 3);

		final actualIdentity = actual.getNominalIdentity();
		final actualAbstract = actualIdentity == null
			|| index == null ? null : index.getAbstractByFullName(actualIdentity.getCanonicalName());
		final actualBindings = abstractBindings(actualAbstract, actual);
		if (actualBindings != null) {
			final via = uniqueCompatible([
				for (type in actualAbstract.getImplicitToTypes())
					TyTypeSubstitution.apply(type, actualBindings)
			], expected);
			if (via != null)
				return new TyImplicitConversionPlan(ABSTRACT_TO, actual, expected, via, 2,
					TyTypeSubstitution.apply(actualAbstract.getUnderlyingType(), actualBindings), actualAbstract.isCoreType());
		}

		final expectedIdentity = expected.getNominalIdentity();
		final expectedAbstract = expectedIdentity == null
			|| index == null ? null : index.getAbstractByFullName(expectedIdentity.getCanonicalName());
		final expectedBindings = abstractBindings(expectedAbstract, expected);
		if (expectedBindings != null) {
			final fromTypes = [
				for (type in expectedAbstract.getImplicitFromTypes())
					TyTypeSubstitution.apply(type, expectedBindings)
			];
			var via = uniqueCompatible(fromTypes, actual, true);
			if (via == null && depth < MAX_FROM_CHAIN)
				via = nestedFrom(index, fromTypes, actual, depth);
			if (via != null)
				return new TyImplicitConversionPlan(ABSTRACT_FROM, actual, expected, via, via.isDynamic() ? 1 : 2,
					TyTypeSubstitution.apply(expectedAbstract.getUnderlyingType(), expectedBindings), expectedAbstract.isCoreType());
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
		Whether a declared abstract conversion preserves the stored value.

		An output conversion exposes the exact storage type. An input conversion
		accepts that same type, or stores its value through Dynamic. A core type's header
		conversion is a cast, because the target owns its representation. A different
		representation can require executable conversion logic and must not become
		a plain typed cast here.
	**/
	public function isRepresentationPreservingAbstractConversion():Bool {
		// A `@:coreType` abstract has no backing type: its target defines the representation,
		// and Haxe 4.3.7 types its header conversion (`abstract Async to Handle`) as a cast.
		if (coreTypeCast && (isAbstractTo() || kind == ABSTRACT_FROM))
			return true;
		if (backingType == null)
			return false;
		if (isAbstractTo())
			return backingType.getSemanticKey() == expectedType.getSemanticKey();
		if (kind == ABSTRACT_FROM)
			return backingType.isDynamic() || backingType.getSemanticKey() == actualType.getSemanticKey();
		return false;
	}

	/** Materialize the already-selected conversion in the shared typed body. **/
	public function apply(expression:TypedExpr):TypedExpr {
		if (expression.getType().getSemanticKey() != actualType.getSemanticKey())
			throw "implicit conversion operand differs from its selected source type";
		if (kind == EXACT)
			return expression.withType(expectedType);
		return TypedExpr.castValue(expression, expectedType.getDisplay(), expectedType, expression.getPosition(),
			isRepresentationPreservingAbstractConversion());
	}
}
