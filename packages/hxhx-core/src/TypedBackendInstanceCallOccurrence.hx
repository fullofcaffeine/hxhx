/**
	Retain the selected instance declaration and applied types at one exact call.
	The source-shaped marker is transport only: equal text cannot replace this
	object or authorize a target binding. Implicit-this calls have no explicit
	receiver type here; consumers that require one must reject that case.
 */
class TypedBackendInstanceCallOccurrence {
	final owner:String;
	final revision:String;
	final expression:HxExpr;
	final declaration:TyDeclarationInfo;
	final resultType:TyType;
	final receiverType:Null<TyType>;
	final argumentTypes:Array<TyType>;
	final projectedArgumentTypes:Array<TyType>;
	final fingerprint:String;

	public function new(input:{
		owner:String,
		revision:String,
		source:TypedExpr,
		expression:HxExpr
	}) {
		final selected = input.source == null ? null : input.source.getDeclaration();
		final call = TypedExactCallSource.decodeInstance(input.expression);
		if (input.owner == null
			|| input.revision == null
			|| input.source == null
			|| input.source.getTag() != Call
			|| selected == null
			|| selected.getIsStatic()
			|| selected.getIsEnumConstructor()
			|| call == null
			|| call.owner != selected.getOwner().getCanonicalName()
			|| call.declaration != selected.getIdentity().getCanonicalKey()
			|| call.method != selected.getSignature().getName())
			throw "instance call requires its exact typed declaration and projected marker";
		owner = input.owner;
		revision = input.revision;
		expression = input.expression;
		declaration = selected;
		resultType = input.source.getType();
		final children = input.source.getExpressions();
		final callee = children[0];
		receiverType = callee.getTag() == FieldRead && callee.getExpressions().length == 1 ? callee.getExpressions()[0].getType() : null;
		input.source.assertArgumentBinding();
		argumentTypes = [for (index in 1...children.length) children[index].getType()];
		final named = input.source.getNamedArguments();
		projectedArgumentTypes = named == null ? argumentTypes.copy() : TypedCallArgumentSource.types(named.getArguments());
		if (projectedArgumentTypes.length != call.arguments.length)
			throw "instance call projection has a stale argument count";
		fingerprint = TypedBodyFingerprint.exactExpression(expression);
	}

	public function getExpression():HxExpr
		return expression;

	public function getDeclaration():TyDeclarationInfo
		return declaration;

	public function getResultType():TyType
		return resultType;

	public function getReceiverType():Null<TyType>
		return receiverType;

	public function getArgumentTypes():Array<TyType>
		return argumentTypes.copy();

	/** Internal omissions have null type facts; trailing omissions remain absent, just as in the projected call. */
	public function getProjectedArgumentTypes():Array<TyType>
		return projectedArgumentTypes.copy();

	/** Recover operands only after checking the original call marker and its payload. */
	public function getCall():TypedExactCallSource.TypedExactInstanceCall {
		if (fingerprint != TypedBodyFingerprint.exactExpression(expression))
			throw "instance call marker was mutated";
		final call = TypedExactCallSource.decodeInstance(expression);
		if (call == null)
			throw "instance call lost its projected marker";
		return call;
	}

	public function assertCurrent(expectedOwner:String, expectedRevision:String):Void {
		if (owner != expectedOwner || revision != expectedRevision)
			throw "instance call belongs to another executable or revision";
		getCall();
	}
}
