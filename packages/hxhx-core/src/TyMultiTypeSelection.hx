/** A known multi-type declaration must never fall back to ordinary abstract allocation after rejection. */
enum TyMultiTypeSelectionResult {
	Ordinary;
	Selected(plan:TyMultiTypeSelection);
	Rejected(reason:String);
}

/**
	Select the first applicable declared conversion for an applied multi-type abstract.
	Each candidate has an isolated solver. The result preserves the source abstract,
	exact conversion declaration, and specialized callable type separately from runtime storage.
	This plan selects types only; construction operands and target execution need their own lowering.
 */
class TyMultiTypeSelection {
	final owner:TyAbstractInfo;
	final constructed:TyType;
	final declaration:TyDeclarationInfo;
	final callable:TyType;

	function new(owner:TyAbstractInfo, constructed:TyType, declaration:TyDeclarationInfo, callable:TyType) {
		this.owner = owner;
		this.constructed = constructed;
		this.declaration = declaration;
		this.callable = callable;
	}

	public function getDeclaration():TyDeclarationInfo
		return declaration;

	public function getConstructedType():TyType
		return constructed;

	public function getCallableType():TyType
		return callable;

	public function getStorageType():TyType
		return callable.getFunctionReturn();

	/** A matching name cannot substitute another program's provider or a different type application. */
	public function assertCurrent(index:TyperIndex, type:TyType):Void {
		if (index.getAbstractByFullName(owner.getIdentity().getCanonicalName()) != owner
			|| type.getSemanticKey() != constructed.getSemanticKey()
			|| owner.getDeclarations().indexOf(declaration) < 0)
			throw "multi-type selection belongs to another provider or type application";
	}

	/** Follow only arguments explicitly named by the policy, using exact abstract declarations and binders. */
	static function follow(index:TyperIndex, type:TyType):Null<TyType> {
		var current = type;
		final visited = new haxe.ds.StringMap<Bool>();
		while (current.getNominalIdentity() != null) {
			final identity = current.getNominalIdentity().getCanonicalName();
			final abstractInfo = index.getAbstractByFullName(identity);
			if (abstractInfo == null)
				return current;
			if (visited.exists(identity) || abstractInfo.getTypeParameterIds().length != current.getTypeArguments().length)
				return null;
			visited.set(identity, true);
			current = TyTypeSubstitution.apply(abstractInfo.getUnderlyingType(),
				TyTypeSubstitution.bind(abstractInfo.getTypeParameterIds(), current.getTypeArguments(), identity));
		}
		return current;
	}

	public static function select(index:TyperIndex, type:TyType):TyMultiTypeSelectionResult {
		final identity = type.getNominalIdentity();
		final owner = identity == null ? null : index.getAbstractByFullName(identity.getCanonicalName());
		if (owner == null || owner.getMultiTypePolicy() == null)
			return Ordinary;
		final arguments = type.getTypeArguments();
		final parameters = owner.getTypeParameterIds();
		if (parameters.length != arguments.length)
			return Rejected("multi-type owner arguments are incomplete");
		for (selected in owner.getMultiTypePolicy().getParameters()) {
			final ordinal = selected.parameter.getOrdinal();
			if (!TyAbstractMethodConversion.complete(arguments[ordinal]) || arguments[ordinal].isTypeParameter())
				return Rejected("multi-type specialization parameters must be known");
			if (selected.followAbstracts) {
				final followed = follow(index, arguments[ordinal]);
				if (followed == null)
					return Rejected("multi-type abstract following is cyclic or unresolved");
				arguments[ordinal] = followed;
			}
		}
		final bindings = TyTypeSubstitution.bind(parameters, arguments, identity.getCanonicalName());
		final underlying = TyTypeSubstitution.apply(owner.getUnderlyingType(), bindings);
		if (!TyAbstractMethodConversion.complete(underlying))
			return Rejected("multi-type backing arguments are unresolved");
		for (declaration in owner.getDeclarations()) {
			if (!declaration.getIsStatic() || !TyAbstractMethodConversion.hasConversion(declaration.getMetadata(), "to"))
				continue;
			final signature = TyTypeSubstitution.apply(TyCallableSignature.fromDeclaration(declaration).getFunctionType(), bindings);
			final inputs = signature.getFunctionParameters();
			if (inputs.length == 0 || inputs[0].isOptional || inputs[0].isRest)
				continue;
			final solver = new TyInferenceSolver("multi-type-candidate");
			final variables = new haxe.ds.StringMap<TyInferenceTerm>();
			for (parameter in declaration.getTypeParameterIds())
				variables.set(parameter.getCanonicalKey(), solver.fresh());
			function term(type:TyType):TyInferenceTerm
				return TyAbstractMethodConversion.term(type, variables);
			if (!solver.constrain(term(inputs[0].type), TyInferenceSolver.fromType(underlying)))
				continue;
			final bounds = declaration.getResolvedTypeParameterConstraints();
			var valid = true;
			for (parameter in declaration.getTypeParameterIds()) {
				final key = parameter.getCanonicalKey();
				final supplied = solver.preview(variables.get(key));
				if (!TyAbstractMethodConversion.complete(supplied)) {
					valid = false;
					break;
				}
				if (bounds.exists(key))
					for (bound in bounds.get(key)) {
						final expected = solver.preview(term(TyTypeSubstitution.apply(bound, bindings)));
						if (!TyAbstractMethodConversion.acceptsBound(index, expected, supplied)
							&& !TyEnumValueCompatibility.accepts(index, expected, supplied)
							&& TyImplicitConversionPlan.select(index, expected, supplied) == null) {
							valid = false;
							break;
						}
					}
				if (!valid)
					break;
			}
			if (!valid)
				continue;
			final callable = solver.preview(term(signature));
			if (!TyAbstractMethodConversion.complete(callable))
				continue;
			return Selected(new TyMultiTypeSelection(owner, type, declaration, callable));
		}
		return Rejected("multi-type abstract " + type.getCanonicalDisplay() + " has no applicable declared conversion");
	}
}
