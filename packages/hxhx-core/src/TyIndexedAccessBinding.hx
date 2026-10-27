/**
	Keep an indexed occurrence's selected helper through inference and executable
	replay. Similar source text cannot reuse the original operands' constraints.
	A conversion-only binding is allowed only when the abstract has no indexed helpers.
 */
class TyIndexedAccessBinding {
	final source:HxExpr;
	final fingerprint:String;

	public final receiver:HxExpr;

	final arguments:Array<HxExpr>;

	public final declaration:Null<TyDeclarationInfo>;
	public final conversion:Null<TyType>;

	public function new(source:HxExpr, receiver:HxExpr, arguments:Array<HxExpr>, ?declaration:TyDeclarationInfo, ?conversion:TyType) {
		if ((declaration == null) == (conversion == null))
			throw "indexed binding requires exactly one helper or declared conversion";
		this.source = source;
		fingerprint = TypedBodyFingerprint.exactExpression(source);
		this.receiver = receiver;
		this.arguments = arguments.copy();
		this.declaration = declaration;
		this.conversion = conversion;
	}

	/** Copy the list while retaining each original operand object. */
	public function getArguments():Array<HxExpr>
		return arguments.copy();

	public function owns(candidate:HxExpr):Bool {
		if (candidate != source)
			return false;
		if (fingerprint != TypedBodyFingerprint.exactExpression(source))
			throw "indexed source changed after declaration selection";
		return true;
	}
}
