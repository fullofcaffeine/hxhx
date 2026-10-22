/**
	One projected construction and the applied types selected by its typed owner.

	For new Box<String>(value), the application retains the original constructor,
	its String parameter, and its substituted backing type. The projected argument
	objects remain in source order. They are inputs to a later call plan, not proof
	that conversions, receiver storage, or native execution are implemented.
 */
class TypedBackendConstructorOccurrence {
	final ownerIdentity:String;
	final bodyRevision:String;
	final expression:HxExpr;
	final arguments:Array<HxExpr>;
	final projectedArguments:Array<HxExpr>;
	final sourceIdentity:String;
	final constructedType:TyType;
	final application:Null<TypedConstructorApplication>;
	final superCall:Bool;
	final operandTypes:Array<TyType>;
	final operandKinds:Array<TyCallAlignment.TyCallOperandKind>;

	public function new(input:{
		ownerIdentity:String,
		bodyRevision:String,
		source:TypedExpr,
		typePath:String,
		arguments:Array<HxExpr>
	}) {
		if (input.ownerIdentity == null || input.ownerIdentity.length == 0 || input.bodyRevision == null || input.bodyRevision.length == 0
			|| input.source == null || input.arguments == null)
			throw "constructor occurrence requires an exact typed construction and executable revision";
		final children = input.source.getExpressions();
		superCall = input.source.getTag() == Call && children.length > 0 && children[0].getTag() == SuperValue;
		if ((!superCall && input.source.getTag() != NewValue) || (superCall && !input.source.getType().isVoid()))
			throw "constructor occurrence requires allocation or a Void parent call";
		if (input.arguments.length != children.length - (superCall ? 1 : 0))
			throw "constructor projection changed the typed argument count";
		final operands = superCall ? children.slice(1) : children;
		operandKinds = TypedExpr.operandKinds(operands);
		operandTypes = TypedExpr.operandTypes(operands, operandKinds);
		ownerIdentity = input.ownerIdentity;
		bodyRevision = input.bodyRevision;
		constructedType = superCall ? children[0].getType() : input.source.getType();
		application = input.source.getConstructorApplication();
		if (application != null)
			application.assertResult(constructedType);
		arguments = input.arguments.copy();
		// Source-shaped targets need explicit interior omissions. Native transport
		// still reads the original operands and binding, so each effect remains once
		// in authored order and synthetic nulls never become source operands.
		projectedArguments = application == null ? arguments.copy() : TypedCallArgumentSource.arguments(application.requireArgumentBinding(operandTypes,
			operandKinds), arguments);
		expression = superCall ? ECall(ESuper, projectedArguments.copy()) : ENew(input.typePath, projectedArguments.copy());
		sourceIdentity = TypedBodyFingerprint.exactExpression(expression);
	}

	public function getExpression():HxExpr
		return expression;

	/** Parent calls initialize the existing receiver rather than allocating the applied owner type. */
	public function getIsSuperCall():Bool
		return superCall;

	public function getConstructedType():TyType
		return constructedType;

	public function getArguments():Array<HxExpr> {
		assertCurrent();
		return arguments.copy();
	}

	/** Missing or implicit selection stays explicit until a consumer implements that construction path. */
	public function requireApplication():TypedConstructorApplication {
		assertCurrent();
		if (application == null)
			throw "unresolved constructor has no selected application";
		return application;
	}

	/**
		Check supplied operands against the exact applied constructor before native transport.
		Omission stays distinct from a supplied null. Shared call validation owns optional
		skipping and rest membership; this occurrence supplies unchanged source-order types.
		The retained proof includes shared structural and inheritance checks made before projection.
	 */
	public function requireArgumentBinding():TyCallArgumentBinding {
		final selected = requireApplication();
		return selected.requireArgumentBinding(operandTypes, operandKinds);
	}

	public function assertOwner(owner:String, revision:String):Void {
		if (ownerIdentity != owner || bodyRevision != revision)
			throw "constructor occurrence belongs to another executable or revision";
	}

	/** Reject replacement operands and nested edits before a backend uses retained typing facts. */
	public function assertCurrent():Void {
		switch expression {
			case ENew(_, values) | ECall(ESuper, values):
				if (values.length != projectedArguments.length)
					throw "constructor occurrence arguments were replaced";
				for (index in 0...values.length)
					if (values[index] != projectedArguments[index])
						throw "constructor occurrence arguments were replaced";
			case _:
				throw "constructor occurrence lost its construction expression";
		}
		if (sourceIdentity != TypedBodyFingerprint.exactExpression(expression))
			throw "constructor occurrence argument structure was mutated";
	}
}
