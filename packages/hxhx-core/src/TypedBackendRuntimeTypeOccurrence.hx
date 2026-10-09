/**
	One runtime type operation bound to its exact executable and projected object.

	The owner and revision identify the typed body. The marker object identifies
	this occurrence inside its projection. Keeping the evaluated value separately
	also detects mutation of the source-shaped marker's argument array.
**/
class TypedBackendRuntimeTypeOccurrence {
	final ownerIdentity:String;
	final bodyRevision:String;
	final target:TypedRuntimeTypeTarget;
	final expression:HxExpr;
	final value:Null<HxExpr>;
	final valueType:Null<TyType>;

	public function new(ownerIdentity:String, bodyRevision:String, target:TypedRuntimeTypeTarget, ?value:HxExpr, ?valueType:TyType) {
		if (ownerIdentity == null || ownerIdentity.length == 0 || bodyRevision == null || bodyRevision.length == 0 || target == null)
			throw "runtime type occurrence requires exact owner, revision, and target";
		if ((value == null) != (valueType == null))
			throw "runtime type test requires its evaluated value and exact source type together";
		this.ownerIdentity = ownerIdentity;
		this.bodyRevision = bodyRevision;
		this.target = target;
		this.value = value;
		this.valueType = valueType;
		this.expression = value == null ? ECall(EIdent(TypedRuntimeTypeSource.VALUE), []) : ECall(EIdent(TypedRuntimeTypeSource.TEST), [value]);
	}

	public function getExpression():HxExpr
		return expression;

	public function getTarget():TypedRuntimeTypeTarget
		return target;

	/** Null denotes a class value; a type test has exactly one evaluated operand. */
	public function getValue():Null<HxExpr>
		return value;

	/** Preserve the typed operand before target erasure; class values have no evaluated operand type. */
	public function getValueType():Null<TyType>
		return valueType;

	public function assertOwner(owner:String, revision:String):Void {
		if (ownerIdentity != owner || bodyRevision != revision)
			throw "runtime type occurrence belongs to another executable or revision";
	}

	/** Reject changed marker contents before a backend relies on the retained fact. */
	public function assertCurrent():Void {
		final valid = switch (expression) {
			case ECall(EIdent(TypedRuntimeTypeSource.VALUE), arguments): value == null && arguments.length == 0;
			case ECall(EIdent(TypedRuntimeTypeSource.TEST), arguments): value != null && arguments.length == 1 && arguments[0] == value;
			case _: false;
		};
		if (!valid)
			throw "runtime type occurrence marker was mutated";
	}
}
