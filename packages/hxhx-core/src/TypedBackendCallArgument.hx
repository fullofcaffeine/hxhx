/**
	Retain a call argument's semantic type at its original projected occurrence.
	Targets need this type when passing values to a Dynamic runtime operation:
	Boolean and integer values can share a native representation. The executable
	identity, revision, and operand fingerprint prevent borrowing another call's type.
**/
class TypedBackendCallArgument {
	public final expression:HxExpr;
	public final type:TyType;

	/** Exact destination selected by shared argument alignment, absent for unresolved calls. */
	public final expectedType:Null<TyType>;

	final owner:String;
	final revision:String;
	final fingerprint:String;

	public function new(owner:String, revision:String, source:TypedExpr, expression:HxExpr, ?expectedType:TyType) {
		if (owner == null || owner.length == 0 || revision == null || revision.length == 0 || source == null || expression == null)
			throw "call argument requires its exact executable and typed operand";
		this.owner = owner;
		this.revision = revision;
		this.expression = expression;
		type = source.getType();
		this.expectedType = expectedType;
		fingerprint = TypedBodyFingerprint.exactExpression(expression);
	}

	public function assertCurrent(owner:String, revision:String):Void {
		if (owner != this.owner || revision != this.revision || fingerprint != TypedBodyFingerprint.exactExpression(expression))
			throw "call argument belongs to another body or changed after projection";
	}
}
