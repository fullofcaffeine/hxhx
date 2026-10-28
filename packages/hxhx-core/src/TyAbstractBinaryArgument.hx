/**
	How one source operand reaches one parameter of a selected abstract binary helper.

	`Converted` is the ordinary case: an executable conversion plan, including the
	exact no-op plan. `IndexedNullableAdmission` is the indexed-update-only case
	where a raw `Null<A>` getter value is passed unchanged to a parameter of exactly
	the same applied abstract `A`. It carries no executable step.
 */
private enum BinaryArgumentEvidence {
	Converted(plan:TyAbstractBinaryConversion);
	IndexedNullableAdmission(operand:TyIndexedNullableAbstractOperand, expected:TyType);
}

/**
	Closed argument fact retained by `TyBoundAbstractBinaryOperator` for each source operand.

	Why: upstream Haxe types `counters["x"] += 2` over `Map<String, MapCounter>` as a
	call to `MapCounter.compound(a:MapCounter, b:Int)` whose first actual argument is
	still the raw `Null<MapCounter>` getter result. There is no conversion node in
	between. Representing that as a `TyAbstractBinaryConversion` would claim an
	executable unwrap that does not exist, so the two cases are separate variants.

	What:
	- `converted(plan)` wraps every ordinary selection; ordinary selection never
	  produces anything else.
	- The indexed admission can be created only by `TyAbstractBinaryBinding` from one
	  checked `TyIndexedNullableAbstractOperand`. It belongs to that operand's getter
	  occurrence, exposes the original nullable actual type and the exact applied
	  expected parameter, and never converts a value.

	How consumers use it: ordinary lowering calls `requireConversion()`, which rejects
	the admission, so a later stage cannot silently lower a nullable value as if it
	had been converted. Indexed selection checks `admitsSource`/`validateSource` so
	the admission cannot move to the right-hand operand or another update.
 */
class TyAbstractBinaryArgument {
	final evidence:BinaryArgumentEvidence;

	function new(evidence:BinaryArgumentEvidence)
		this.evidence = evidence;

	/** Wrap one executable conversion selected by the existing ordinary rules. */
	public static function converted(plan:TyAbstractBinaryConversion):TyAbstractBinaryArgument {
		if (plan == null)
			throw "binary argument requires its selected conversion";
		return new TyAbstractBinaryArgument(Converted(plan));
	}

	/** Only the indexed binary entry may admit the raw getter, and only to its exact applied abstract. */
	@:allow(TyAbstractBinaryBinding)
	static function indexed(operand:TyIndexedNullableAbstractOperand, expected:TyType):TyAbstractBinaryArgument {
		if (operand == null || !operand.admits(expected, operand.originalType))
			throw "indexed argument has another applied parameter";
		return new TyAbstractBinaryArgument(IndexedNullableAdmission(operand, expected));
	}

	/** The source operand's type before any conversion; the raw nullable getter type for an admission. */
	public function getActualType():TyType
		return switch evidence {
			case Converted(plan): plan.getActualType();
			case IndexedNullableAdmission(operand, _): operand.originalType;
		};

	/** The selected helper parameter type this operand is checked against. */
	public function getExpectedType():TyType
		return switch evidence {
			case Converted(plan): plan.getExpectedType();
			case IndexedNullableAdmission(_, expected): expected;
		};

	/** Orientation score; an admission ranks like an exact match because the applied abstract is identical. */
	public function getScore():Int
		return switch evidence {
			case Converted(plan): plan.getScore();
			case IndexedNullableAdmission(_, _): 4;
		};

	/** Ordinary lowering cannot silently execute a checked indexed admission. */
	public function requireConversion():TyAbstractBinaryConversion
		return switch evidence {
			case Converted(plan): plan;
			case IndexedNullableAdmission(_, _): throw "indexed nullable argument has no executable conversion";
		};

	/**
		The executable plan behind a converted operand, or null for the raw indexed admission.
		Only the completed indexed update may ask: it passes an admitted getter value unchanged.
	 */
	@:allow(TyIndexedUpdateOutcome)
	function executableConversion():Null<TyAbstractBinaryConversion>
		return switch evidence {
			case Converted(plan): plan;
			case IndexedNullableAdmission(_, _): null;
		};

	/** True for every conversion, and for an admission only at its own getter occurrence. */
	public function admitsSource(source:HxExpr):Bool
		return switch evidence {
			case Converted(_): true;
			case IndexedNullableAdmission(operand, _): source == operand.query.getterSource;
		};

	/**
		Revalidate an admission against its exact source occurrence and current inference.
		A conversion has no source-specific identity, so it has nothing extra to check here.
	 */
	public function validateSource(source:HxExpr, environment:TyFunctionEnv, ?retainedInference:TyFunctionInference):Void {
		switch evidence {
			case Converted(_):
			case IndexedNullableAdmission(operand, expected):
				operand.validate(environment, retainedInference);
				if (!admitsSource(source) || !operand.admits(expected, getActualType()))
					throw "indexed argument admission belongs to another source position";
		}
	}
}
