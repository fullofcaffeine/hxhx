/** A method value needs receiver binding; a callee and a write retain ordinary member syntax. */
enum TypedMethodUse {
	ValueRead;
	DirectCall;
	WriteTarget;
}

/**
	One exact instance-method selection inside a projected executable.
	The selected declaration and receiver come from typing. Targets use the role
	to bind stored values without changing direct calls or dynamic-method writes.
**/
class TypedBackendMethodOccurrence {
	final owner:String;
	final revision:String;
	final expression:HxExpr;
	final declaration:TyDeclarationInfo;
	final use:TypedMethodUse;
	final fingerprint:String;

	public function new(input:{
		owner:String,
		revision:String,
		source:TypedExpr,
		expression:HxExpr,
		use:TypedMethodUse
	}) {
		final selected = input.source == null ? null : input.source.getDeclaration();
		if (input.owner == null
			|| input.owner.length == 0
			|| input.revision == null
			|| input.revision.length == 0
			|| input.source == null
			|| input.use == null
			|| input.source.getTag() != FieldRead
			|| selected == null
			|| selected.getIsStatic()
			|| selected.getIsEnumConstructor()
			|| input.source.getFieldInfo() != null
			|| !input.source.getType().isFunction()
			|| input.source.getExpressions().length != 1)
			throw "method occurrence requires an exact instance selection";
		switch (input.expression) {
			case EField(_, name) if (name == selected.getSignature().getName()):
			case _:
				throw "method occurrence requires its projected receiver selection";
		}
		owner = input.owner;
		revision = input.revision;
		expression = input.expression;
		declaration = selected;
		use = input.use;
		fingerprint = TypedBodyFingerprint.exactExpression(expression);
	}

	public function getExpression():HxExpr
		return expression;

	public function getDeclaration():TyDeclarationInfo
		return declaration;

	public function getUse():TypedMethodUse
		return use;

	/** The executable owner also verifies that this exact object remains in its body. */
	public function assertCurrent(expectedOwner:String, expectedRevision:String):Void {
		if (owner != expectedOwner || revision != expectedRevision)
			throw "method occurrence belongs to another executable or revision";
		if (fingerprint != TypedBodyFingerprint.exactExpression(expression))
			throw "method occurrence structure was mutated";
	}
}
