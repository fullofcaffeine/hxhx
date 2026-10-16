/** Exact operand types for collection operations selected by shared control lowering. */
enum TypedCollectionControl {
	Iterate(iterableType:TyType, isRange:Bool);
	Append(arrayType:TyType, valueType:TyType);
}

/**
	Keep collection storage decisions attached to the original projected operation.
	A target needs the iterable type and appended value type after source-shaped
	projection. Matching printed syntax is insufficient, especially for Dynamic
	elements whose native representation differs from ordinary Boolean storage.
 */
class TypedBackendCollectionControl {
	public final expression:HxExpr;
	public final operation:TypedCollectionControl;

	final owner:String;
	final revision:String;
	final fingerprint:String;
	final operands:Array<HxExpr>;

	public function new(input:{
		owner:String,
		revision:String,
		source:TypedExpr,
		expression:HxExpr
	}) {
		if (input.owner.length == 0 || input.revision.length == 0 || input.source == null)
			throw "collection control requires its typed executable owner";
		owner = input.owner;
		revision = input.revision;
		expression = input.expression;
		final children = input.source.getExpressions();
		if (children.length != 2)
			throw "collection control requires its two selected operands";
		operation = switch [input.source.getTag(), expression] {
			case [ControlFor, ELoweredControl(For(_), destination, values, _)] if (values.length == 2):
				final target = input.source.getControlTarget();
				if (target == null || destination != target.getCanonicalIdentity())
					throw "collection iteration lost its selected loop destination";
				Iterate(children[0].getType(), children[0].getTag() == FixedRange);
			case [ArrayAppend, ELoweredControl(ArrayAppend, "", values, _)] if (values.length == 2):
				Append(children[0].getType(), children[1].getType());
			case _: throw "collection control differs from its typed operation";
		};
		operands = switch expression {
			case ELoweredControl(_, _, values, _): values.copy();
			case _: throw "collection control lost its projected operands";
		};
		fingerprint = TypedBodyFingerprint.exactExpression(expression);
	}

	/** Copied, replaced, and mutated operands cannot borrow this operation's types. */
	public function assertCurrent(owner:String, revision:String):Void {
		if (this.owner != owner || this.revision != revision || fingerprint != TypedBodyFingerprint.exactExpression(expression))
			throw "collection control belongs to another executable or changed after projection";
		switch expression {
			case ELoweredControl(_, _, values, _) if (values.length == operands.length):
				for (index in 0...values.length)
					if (values[index] != operands[index])
						throw "collection control operands were replaced";
			case _:
				throw "collection control lost its original operands";
		}
	}
}
