/**
	A generic class declaration used as a value, before a Class<T> use chooses T.
	An inferred alias retains this fact. An explicit Class<T> annotation consumes
	it, so an erased handle cannot later borrow the declaration's generic freedom.
	The runtime target remains the existing exact descriptor; no instance is made.
 */
class TyClassValueScheme {
	final target:TypedRuntimeTypeTarget;
	final parameters:Array<TyTypeParameterId>;

	function new(target:TypedRuntimeTypeTarget, parameters:Array<TyTypeParameterId>) {
		this.target = target;
		this.parameters = parameters.copy();
	}

	/** Only resolved generic class providers introduce a scheme; source spelling is not authority. */
	public static function select(target:TypedRuntimeTypeTarget, index:TyperIndex):Null<TyClassValueScheme> {
		if (index == null || target == null || !(target.getKind().match(ArrayCore) || target.getKind().match(Nominal(_))))
			return null;
		final owner = index.getByFullName(target.requireDeclarationIdentity().getCanonicalName());
		if (owner == null || !Std.isOfType(owner, TyClassInfo))
			return null;
		final parameters = TyNominalApplication.parameterIds(owner);
		return parameters.length == 0 ? null : new TyClassValueScheme(target, parameters);
	}

	public function getParameters():Array<TyTypeParameterId>
		return parameters.copy();

	public function getIdentity():TyNominalTypeId
		return target.requireDeclarationIdentity();

	public function getSemanticKey():String
		return CompilerCacheIdentity.encode([target.getSemanticKey()].concat(parameters.map(parameter -> parameter.getCanonicalKey())));

	/** An incomplete preview is candidate evidence only; it never becomes the stored alias type. */
	public function preview():TyType
		return application(parameters.map(_ -> TyType.unknown()));

	public function application(arguments:Array<TyType>):TyType {
		if (arguments.length != parameters.length)
			throw "class-value application changed declaration arity";
		return TyType.nominal(new TyNominalTypeId("Class"), [TyType.nominal(getIdentity(), arguments)]);
	}

	/** The target hint describes storage only; the semantic key retains the unspecialized declaration. */
	public function getCanonicalDisplay():String
		return application(parameters.map(_ -> TyType.fromHintText("Dynamic"))).getCanonicalDisplay();

	public function accepts(expected:TyType):Bool {
		final context = expected.unwrapNull();
		final identity = context.getNominalIdentity();
		final arguments = context.getTypeArguments();
		if (identity == null || identity.getCanonicalName() != "Class" || arguments.length != 1)
			return false;
		final instance = arguments[0];
		if (instance.isDynamic())
			return true;
		return instance.getNominalIdentity() != null
			&& instance.getNominalIdentity().equals(getIdentity())
			&& instance.getTypeArguments().length == parameters.length;
	}

	/** Introduce or consume a scheme while retaining the original runtime expression as the only child. */
	public static function convert(value:TypedExpr, expected:TyType):Null<TypedExpr> {
		if (expected == null || expected.hasUnknownComponent() || value.getType().getSemanticKey() == expected.getSemanticKey())
			return null;
		final source = value.getType().getClassValueScheme();
		if (source != null && source.accepts(expected))
			return TypedExpr.castValue(value, expected.getCanonicalDisplay(), expected, value.getPosition(), true);
		final destination = expected.getClassValueScheme();
		final runtime = value.getRuntimeTypeTarget();
		if (destination != null
			&& value.getTag() == RuntimeTypeValue
			&& runtime != null
			&& runtime.getSemanticKey() == destination.target.getSemanticKey()
			&& value.getType().getSemanticKey() == runtime.getValueType().getSemanticKey())
			return TypedExpr.castValue(value, expected.getCanonicalDisplay(), expected, value.getPosition(), true);
		return null;
	}
}
