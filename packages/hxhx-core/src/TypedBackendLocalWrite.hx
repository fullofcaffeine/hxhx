/**
	Preserve both types at a local storage boundary after source-shaped projection.
	An initializer's type can differ from its declared destination, as with Int to
	Dynamic. The exact operand, binding, and body revision prevent a backend from
	borrowing conversion facts from a same-spelled local or a rebuilt body.
 */
class TypedBackendLocalWrite {
	public final expression:HxExpr;
	public final projectedName:String;
	public final binding:TyLocalBinding;
	public final sourceType:TyType;

	final owner:String;
	final revision:String;
	final fingerprint:String;

	public function new(input:{
		owner:String,
		revision:String,
		expression:HxExpr,
		projectedName:String,
		binding:TyLocalBinding,
		source:TypedExpr
	}) {
		if (input.binding == null
			|| input.source == null
			|| input.expression == null
			|| input.binding.getIdentity().getOwnerIdentity() != input.owner)
			throw "local write requires its exact typed owner and operand";
		owner = input.owner;
		revision = input.revision;
		expression = input.expression;
		projectedName = input.projectedName;
		binding = input.binding;
		sourceType = input.source.getType();
		fingerprint = TypedBodyFingerprint.exactExpression(expression);
	}

	/** Recognize the exact destination/operand pair after source-shaped projection. */
	public static function matchesExpression(node:HxExpr, name:String, operand:HxExpr):Bool {
		return switch node {
			case EBinop(op, EIdent(target), value): target == name && value == operand && ["=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>=", ">>>="].indexOf(op) >= 0;
			case EVariableDeclaration(target, _, value, _, _, _): target == name && value == operand;
			case _: false;
		};
	}

	public function assertCurrent(owner:String, revision:String):Void {
		if (this.owner != owner || this.revision != revision || fingerprint != TypedBodyFingerprint.exactExpression(expression))
			throw "local write belongs to another body or was changed after projection";
	}
}
