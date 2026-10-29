/** One arrow entry retains each operand's type before target storage selection. */
typedef TypedBackendMapEntry = {
	final key:HxExpr;
	final value:HxExpr;
	final keyType:TyType;
	final valueType:TyType;
};

/**
	Array literals and anonymous objects retain their typed children.
	The projected object and child identities belong to one executable revision.
	This records types and order only; each target must still implement conversions,
	storage, and publication before it can execute the aggregate.
 */
class TypedBackendAggregateOccurrence {
	final ownerIdentity:String;
	final bodyRevision:String;
	final expression:HxExpr;
	final type:TyType;
	final children:Array<HxExpr>;
	final childTypes:Array<TyType>;
	final mapEntries:Array<TypedBackendMapEntry> = [];
	final fingerprint:String;

	public function new(input:{
		ownerIdentity:String,
		bodyRevision:String,
		source:TypedExpr,
		children:Array<HxExpr>
	}) {
		if (input.ownerIdentity == null
			|| input.bodyRevision == null
			|| input.source == null
			|| input.children == null
			|| input.children.length != input.source.getExpressions().length)
			throw "aggregate occurrence requires its typed owner and ordered children";
		ownerIdentity = input.ownerIdentity;
		bodyRevision = input.bodyRevision;
		type = input.source.getType();
		children = input.children.copy();
		childTypes = [for (child in input.source.getExpressions()) child.getType()];
		final identity = type.getNominalIdentity();
		if (input.source.getTag() == ArrayDecl && identity != null && identity.getCanonicalName() == "haxe.ds.Map") {
			final typedChildren = input.source.getExpressions();
			for (index in 0...children.length) {
				final typed = typedChildren[index];
				final operands = typed.getExpressions();
				if (typed.getTag() != Binary || typed.getTexts()[0] != "=>" || operands.length != 2)
					throw "Map aggregate requires typed arrow entries";
				switch children[index] {
					case EBinop("=>", key, value):
						mapEntries.push({
							key: key,
							value: value,
							keyType: operands[0].getType(),
							valueType: operands[1].getType()
						});
					case _:
						throw "Map aggregate lost its projected arrow entry";
				}
			}
		}
		expression = switch input.source.getTag() {
			case ArrayDecl: EArrayDecl(children.copy());
			case Anonymous:
				final names = input.source.getTexts();
				if (names.length != children.length)
					throw "anonymous occurrence has inconsistent field operands";
				EAnon(names.copy(), children.copy());
			case _: throw "aggregate occurrence requires an array or anonymous object";
		};
		fingerprint = TypedBodyFingerprint.exactExpression(expression);
	}

	public function getExpression():HxExpr
		return expression;

	public function getType():TyType
		return type;

	public function getChildren():Array<HxExpr>
		return children.copy();

	public function getChildTypes():Array<TyType>
		return childTypes.copy();

	/** Entry facts refer to the same projected children checked by assertCurrent. */
	public function getMapEntries():Array<TypedBackendMapEntry>
		return mapEntries.copy();

	/** Equal source text cannot substitute another occurrence or replacement child. */
	public function assertCurrent(owner:String, revision:String):Void {
		if (owner != ownerIdentity || revision != bodyRevision)
			throw "aggregate occurrence belongs to another executable or revision";
		final values = switch expression {
			case EArrayDecl(values) | EAnon(_, values): values;
			case _: throw "aggregate occurrence lost its projected expression";
		};
		if (values.length != children.length)
			throw "aggregate occurrence children were replaced";
		for (index in 0...values.length)
			if (values[index] != children[index])
				throw "aggregate occurrence children were replaced";
		if (fingerprint != TypedBodyFingerprint.exactExpression(expression))
			throw "aggregate occurrence structure was mutated";
	}
}
