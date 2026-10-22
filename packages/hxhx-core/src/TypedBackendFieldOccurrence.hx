/** Whether a projected field has a source value receiver whose evaluation must be preserved. */
enum TypedBackendFieldReceiver {
	ImplicitOwner;
	TypeQualifier;
	ValueReceiver;
}

/**
	A field occurrence retains the declaration selected by typing and its exact
	projected expression. Qualified access must not resolve ownership from source
	spelling: an inherited field still belongs to its declaring class. The result
	type is retained separately because applied instance types can specialize it.
 */
class TypedBackendFieldOccurrence {
	final ownerIdentity:String;
	final bodyRevision:String;
	final expression:HxExpr;
	final field:TyFieldInfo;
	final type:TyType;
	final receiver:TypedBackendFieldReceiver;
	final fingerprint:String;
	final propertyStorageAccess:Bool;

	public function new(input:{
		ownerIdentity:String,
		bodyRevision:String,
		source:TypedExpr,
		expression:HxExpr,
		receiver:TypedBackendFieldReceiver
	}) {
		if (input.ownerIdentity == null || input.ownerIdentity.length == 0 || input.bodyRevision == null || input.bodyRevision.length == 0
			|| input.source == null || input.source.getFieldInfo() == null || input.expression == null || input.receiver == null)
			throw "field occurrence requires exact typed ownership";
		switch input.source.getTag() {
			case NameRead | FieldRead:
			case _:
				throw "field occurrence requires a typed field selection";
		}
		switch input.expression {
			case EIdent(_) | EField(_, _):
			case _:
				throw "field occurrence requires its projected field access";
		}
		ownerIdentity = input.ownerIdentity;
		bodyRevision = input.bodyRevision;
		expression = input.expression;
		field = input.source.getFieldInfo();
		propertyStorageAccess = input.source.getHasPropertyStorageAccess();
		type = input.source.getType();
		receiver = input.receiver;
		fingerprint = TypedBodyFingerprint.exactExpression(expression);
	}

	public function getExpression():HxExpr
		return expression;

	public function getField():TyFieldInfo
		return field;

	/** This exact occurrence was admitted as stored access by shared property lowering. */
	public function getHasPropertyStorageAccess():Bool
		return propertyStorageAccess;

	public function getType():TyType
		return type;

	public function getReceiver():TypedBackendFieldReceiver
		return receiver;

	/** Consumers must also prove this exact object remains in their executable body. */
	public function assertCurrent(owner:String, revision:String):Void {
		if (owner != ownerIdentity || revision != bodyRevision)
			throw "field occurrence belongs to another executable or revision";
		if (fingerprint != TypedBodyFingerprint.exactExpression(expression))
			throw "field occurrence structure was mutated";
	}
}
