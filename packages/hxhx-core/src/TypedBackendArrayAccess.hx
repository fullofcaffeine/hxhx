/** The logical indexed operation before a target chooses element storage. */
enum TypedBackendArrayAccessKind {
	Read;
	Write;
	Compound(op:String);
}

/**
	Retain exact receiver, index and element types across source-shaped projection.
	Targets use these facts to distinguish logical Boolean elements from erased
	storage. The occurrence grants no authority to copied syntax or another body.
 */
class TypedBackendArrayAccess {
	public final expression:HxExpr;
	public final receiver:HxExpr;
	public final index:HxExpr;
	public final value:Null<HxExpr>;
	public final kind:TypedBackendArrayAccessKind;
	public final receiverType:TyType;
	public final indexType:TyType;
	public final resultType:TyType;
	public final valueType:Null<TyType>;

	final owner:String;
	final revision:String;
	final fingerprint:String;

	public static function supports(source:TypedExpr):Bool {
		return switch source.getTag() {
			case ArrayAccess: true;
			case Assign | CompoundAssign: source.getExpressions()[0].getTag() == ArrayAccess;
			case _: false;
		};
	}

	public function new(input:{
		owner:String,
		revision:String,
		source:TypedExpr,
		expression:HxExpr
	}) {
		if (input.owner == null || input.owner.length == 0 || input.revision == null || input.revision.length == 0 || input.source == null
			|| !supports(input.source))
			throw "array access requires an exact typed indexed operation";
		owner = input.owner;
		revision = input.revision;
		expression = input.expression;
		kind = switch input.source.getTag() {
			case ArrayAccess: Read;
			case Assign: Write;
			case CompoundAssign: Compound(input.source.getTexts()[0]);
			case _: throw "unsupported typed array access";
		};
		final parts = switch expression {
			case EArrayAccess(array, subscript): {receiver: array, index: subscript, value: null};
			case EBinop(_, EArrayAccess(array, subscript), written): {receiver: array, index: subscript, value: written};
			case _: throw "array access lost its projected operands";
		};
		receiver = parts.receiver;
		index = parts.index;
		value = parts.value;
		switch [kind, expression] {
			case [Read, EArrayAccess(_, _)], [Write, EBinop("=", _, _)]:
			case [Compound(expected), EBinop(actual, _, _)] if (expected == actual):
			case _:
				throw "array access operator differs from its typed operation";
		}
		final selected = kind == Read ? input.source : input.source.getExpressions()[0];
		receiverType = selected.getExpressions()[0].getType();
		indexType = selected.getExpressions()[1].getType();
		resultType = input.source.getType();
		valueType = kind == Read ? null : input.source.getExpressions()[1].getType();
		fingerprint = TypedBodyFingerprint.exactExpression(expression);
	}

	/** Validate operation ownership and retain the original receiver, index and written value objects. */
	public function assertCurrent(owner:String, revision:String):Void {
		if (this.owner != owner || this.revision != revision || fingerprint != TypedBodyFingerprint.exactExpression(expression))
			throw "array access belongs to another executable or changed after projection";
		final unchanged = switch expression {
			case EArrayAccess(array, subscript): array == receiver && subscript == index && value == null;
			case EBinop(_, EArrayAccess(array, subscript), written): array == receiver && subscript == index && written == value;
			case _: false;
		};
		if (!unchanged)
			throw "array access operands were replaced";
	}
}
