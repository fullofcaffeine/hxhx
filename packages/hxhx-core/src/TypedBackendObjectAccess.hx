/** A structural field read or write retains types without inventing a class declaration. */
enum TypedBackendObjectAccessKind {
	Read;
	Write;
	Compound(op:String);
}

/**
	Bind object storage conversions to one projected expression and executable.
	Receiver and value identities reject substituted operands even when their source
	text is equal. Nominal fields continue to use their declaration-owned catalog.
 */
class TypedBackendObjectAccess {
	public final expression:HxExpr;
	public final receiver:HxExpr;
	public final value:Null<HxExpr>;
	public final field:String;
	public final kind:TypedBackendObjectAccessKind;
	public final resultType:TyType;
	public final valueType:Null<TyType>;

	final owner:String;
	final revision:String;
	final fingerprint:String;

	public static function supports(source:TypedExpr):Bool {
		final selected = switch source.getTag() {
			case FieldRead: source;
			case Assign | CompoundAssign: source.getExpressions()[0];
			case _: return false;
		};
		if (selected.getTag() != FieldRead)
			return false;
		final receiverType = selected.getExpressions()[0].getType().unwrapNull();
		return receiverType.isAnonymous() || receiverType.isDynamic();
	}

	public function new(input:{
		owner:String,
		revision:String,
		source:TypedExpr,
		expression:HxExpr
	}) {
		if (input.owner == null || input.owner.length == 0 || input.revision == null || input.revision.length == 0 || input.source == null
			|| !supports(input.source))
			throw "object access requires a structural or Dynamic receiver";
		owner = input.owner;
		revision = input.revision;
		expression = input.expression;
		resultType = input.source.getType();
		kind = switch input.source.getTag() {
			case FieldRead: Read;
			case Assign: Write;
			case CompoundAssign: Compound(input.source.getTexts()[0]);
			case _: throw "unsupported typed object access";
		};
		final parts = switch expression {
			case EField(object, name): {receiver: object, field: name, value: null};
			case EBinop(_, EField(object, name), written): {receiver: object, field: name, value: written};
			case _: throw "object access lost its projected field";
		};
		receiver = parts.receiver;
		field = parts.field;
		value = parts.value;
		final selected = kind == Read ? input.source : input.source.getExpressions()[0];
		if (field != selected.getTexts()[0] || (kind == Read) != (value == null))
			throw "object access does not match its typed operation";
		switch [kind, expression] {
			case [Read, EField(_, _)], [Write, EBinop("=", _, _)]:
			case [Compound(expected), EBinop(actual, _, _)] if (expected == actual):
			case _:
				throw "object access operator differs from its typed operation";
		}
		valueType = kind == Read ? null : input.source.getExpressions()[1].getType();
		fingerprint = TypedBodyFingerprint.exactExpression(expression);
	}

	public function assertCurrent(owner:String, revision:String):Void {
		if (this.owner != owner || this.revision != revision || fingerprint != TypedBodyFingerprint.exactExpression(expression))
			throw "object access belongs to another executable or changed after projection";
		final unchanged = switch expression {
			case EField(object, name): object == receiver && name == field && value == null;
			case EBinop(_, EField(object, name), written): object == receiver && name == field && written == value;
			case _: false;
		};
		if (!unchanged)
			throw "object access operands were replaced";
	}
}
