/**
	Retain the checked type of a branch or loop condition after source projection.
	Dynamic Boolean values need runtime conversion; syntax or a local's spelling
	cannot determine that representation. The owning projection verifies that the
	exact operand still belongs to its current executable body.
**/
class TypedBackendCondition {
	public final expression:HxExpr;
	public final type:TyType;

	final owner:String;
	final revision:String;
	final fingerprint:String;

	public function new(input:{
		owner:String,
		revision:String,
		source:TypedExpr,
		expression:HxExpr
	}) {
		owner = input.owner;
		revision = input.revision;
		expression = input.expression;
		type = input.source.getType();
		fingerprint = TypedBodyFingerprint.exactExpression(expression);
	}

	public function assertCurrent(expectedOwner:String, expectedRevision:String):Void {
		if (owner != expectedOwner || revision != expectedRevision || fingerprint != TypedBodyFingerprint.exactExpression(expression))
			throw "condition belongs to another executable or changed after projection";
	}
}
