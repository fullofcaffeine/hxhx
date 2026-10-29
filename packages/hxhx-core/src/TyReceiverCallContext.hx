/**
	Retain one call's Dynamic input context while its generic receiver is still
	being inferred. Later receiver constraints remain independent. This evidence
	belongs to the exact source call and selected declaration, never to a type
	pair that could authorize another call after the receiver becomes concrete.
 */
class TyReceiverCallContext {
	final source:HxExpr;
	final fingerprint:String;
	final declarationKey:String;
	final parameters:Array<Null<TyType>>;

	public function new(source:HxExpr, declaration:TyDeclarationInfo, parameters:Array<Null<TyType>>) {
		this.source = source;
		fingerprint = TypedBodyFingerprint.exactExpression(source);
		declarationKey = declaration.getIdentity().getCanonicalKey();
		this.parameters = parameters.copy();
	}

	public function owns(expression:HxExpr):Bool
		return source == expression;

	/** Replay validates source and declaration identity before replacing any invocation context. */
	public function apply(expression:HxExpr, declaration:TyDeclarationInfo, current:Array<TyType>):Array<TyType> {
		if (expression != source
			|| fingerprint != TypedBodyFingerprint.exactExpression(expression)
			|| declarationKey != declaration.getIdentity().getCanonicalKey()
			|| current.length != parameters.length)
			throw "receiver call context no longer belongs to this source declaration";
		return [
			for (index in 0...current.length)
				parameters[index] == null ? current[index] : parameters[index]
		];
	}

	/**
		Only receiver-owned holes and fixed supplied arguments contribute evidence.
		Method binders, optional alignment, and rest operands retain their existing
		owners. Unknown components without an explicit Dynamic operand stay open.
	 */
	public static function select(signature:TyFunSig, applied:TyFunSig, binders:Array<TyTypeParameterId>, actual:Array<TyType>,
			order:TyMethodArgumentOrder):Null<Array<Null<TyType>>> {
		if (signature.getArgs().length != actual.length
			|| signature.getArgOptional().indexOf(true) >= 0
			|| signature.getArgRest().indexOf(true) >= 0)
			return null;
		final slots = order.getSlots();
		final result:Array<Null<TyType>> = [];
		var changed = false;
		for (index in 0...actual.length) {
			switch slots[index] {
				case Supplied(source) if (source == index):
				case _:
					return null;
			}
			final owned = TyTypeSubstitution.parameterIdentities(signature.getArgs()[index])
				.filter(parameter -> binders.filter(binder -> binder.getCanonicalKey() == parameter.getCanonicalKey()).length > 0)
				.length > 0;
			final expected = applied.getArgs()[index];
			final context = owned && expected.hasUnknownComponent() ? dynamicContext(expected, actual[index]) : null;
			final selected = context != null
				&& !context.hasUnknownComponent()
				&& TyAssignmentCompatibility.classify(context, actual[index], Unchecked) == Compatible ? context : null;
			result.push(selected);
			if (selected != null)
				changed = true;
		}
		return changed ? result : null;
	}

	/** Fill only holes witnessed by Dynamic, preserving every other part of the receiver application. */
	static function dynamicContext(expected:TyType, actual:TyType):Null<TyType> {
		if (expected.isUnknown())
			return actual.isDynamic() ? actual : null;
		if (!expected.hasUnknownComponent())
			return expected;
		if (expected.isNullable()) {
			final inner = dynamicContext(expected.unwrapNull(), actual.unwrapNull());
			return inner == null ? null : TyType.nullable(inner);
		}
		final owner = expected.getNominalIdentity();
		final other = actual.getNominalIdentity();
		if (owner == null || other == null || !owner.equals(other))
			return null;
		final wanted = expected.getTypeArguments();
		final supplied = actual.getTypeArguments();
		if (wanted.length != supplied.length)
			return null;
		final arguments = new Array<TyType>();
		for (index in 0...wanted.length) {
			final argument = dynamicContext(wanted[index], supplied[index]);
			if (argument == null)
				return null;
			arguments.push(argument);
		}
		return TyType.nominal(owner, arguments);
	}
}
