/**
	Keep a thrown operand's exact type after projection to source-shaped statements.
	The target needs this fact to distinguish Boolean storage from integer storage.
	Object identity and the body revision prevent borrowing a type from another throw.
 */
class TypedBackendThrownValue {
	public final expression:HxExpr;
	public final type:TyType;

	final owner:String;
	final revision:String;
	final fingerprint:String;

	public function new(owner:String, revision:String, source:TypedExpr, expression:HxExpr) {
		if (owner == null || revision == null || source == null || expression == null)
			throw "thrown value requires its exact typed owner and operand";
		this.owner = owner;
		this.revision = revision;
		this.expression = expression;
		type = source.getType();
		fingerprint = TypedBodyFingerprint.exactExpression(expression);
	}

	public function assertCurrent(owner:String, revision:String):Void {
		if (owner != this.owner || revision != this.revision || fingerprint != TypedBodyFingerprint.exactExpression(expression))
			throw "thrown value belongs to another body or was changed after projection";
	}
}
