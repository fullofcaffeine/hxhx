/**
	Retain a checked return operand through expression and statement projection.
	The return operation, rather than its possibly shared literal operand, owns
	the fact. Native targets can then convert that value to its function result.
 */
class TypedBackendReturnOccurrence {
	public final expression:HxExpr;
	public final type:TyType;

	final source:TypedExpr;
	final owner:String;
	final revision:String;
	final fingerprint:String;

	public function new(owner:String, revision:String, source:TypedExpr, expression:HxExpr) {
		if (source == null
			|| source.getTag() != ReturnExpr
			|| source.getExpressions().length > 1
			|| source.getControlTarget() == null)
			throw "return occurrence requires its checked return and destination";
		switch expression {
			case ELoweredControl(Return, target, values, _)
				if (target == source.getControlTarget().getCanonicalIdentity() && values.length == source.getExpressions().length):
			case _:
				throw "return occurrence requires its exact projected operation";
		}
		this.owner = owner;
		this.revision = revision;
		this.source = source;
		this.expression = expression;
		type = source.getExpressions().length == 0 ? TyType.fromHintText("Void") : source.getExpressions()[0].getType();
		fingerprint = TypedBodyFingerprint.exactExpression(expression);
	}

	public function belongsTo(value:TypedExpr):Bool
		return source == value;

	/** Equal text from another operation cannot supply a return conversion contract. */
	public function assertCurrent(owner:String, revision:String):Void {
		if (owner != this.owner || revision != this.revision)
			throw "return occurrence belongs to another executable or revision";
		if (TypedBodyFingerprint.exactExpression(expression) != fingerprint)
			throw "return occurrence changed after projection";
	}
}
