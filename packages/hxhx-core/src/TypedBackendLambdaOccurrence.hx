/**
	Keep an expression lambda's callable contract separate from its body's value type.
	A Dynamic body can satisfy a concrete return contract, but a native target must
	convert its representation at that boundary. Facts belong to one exact projected
	lambda and executable revision; equal source text cannot authorize another use.
 */
class TypedBackendLambdaOccurrence {
	public final expression:HxExpr;
	public final callableType:TyType;
	public final bodyType:TyType;

	final body:HxExpr;
	final owner:String;
	final revision:String;
	final fingerprint:String;
	final returnTypes:Array<TyType> = [];
	final returns:Array<TypedBackendReturnOccurrence> = [];

	public function new(input:{
		owner:String,
		revision:String,
		source:TypedExpr,
		expression:HxExpr,
		returns:Array<TypedBackendReturnOccurrence>
	}) {
		if (input.owner == null
			|| input.revision == null
			|| input.source == null
			|| input.source.getTag() != Lambda
			|| input.source.getExpressions().length != 1
			|| !input.source.getType().isFunction())
			throw "lambda occurrence requires its exact callable and typed body";
		owner = input.owner;
		revision = input.revision;
		expression = input.expression;
		body = switch expression {
			case ELambda(_, value): value;
			case _: throw "lambda occurrence requires its projected lambda";
		};
		callableType = input.source.getType();
		bodyType = input.source.getExpressions()[0].getType();
		collectReturns(input.source.getExpressions()[0], input.returns);
		fingerprint = TypedBodyFingerprint.exactExpression(expression);
	}

	/** Nested lambdas own their returns; only this function's exits enter the contract. */
	function collectReturns(value:TypedExpr, candidates:Array<TypedBackendReturnOccurrence>):Void {
		if (value.getTag() == Lambda)
			return;
		if (value.getTag() == ReturnExpr) {
			final values = value.getExpressions();
			returnTypes.push(values.length == 0 ? TyType.fromHintText("Void") : values[0].getType());
			var selected:Null<TypedBackendReturnOccurrence> = null;
			for (candidate in candidates)
				if (candidate.belongsTo(value)) {
					if (selected != null)
						throw "lambda return has duplicate projected occurrences";
					selected = candidate;
				}
			if (selected == null)
				throw "lambda lost its exact projected return";
			selected.assertCurrent(owner, revision);
			returns.push(selected);
		}
		for (child in value.getExpressions())
			collectReturns(child, candidates);
	}

	/** Select by exact operation identity, never by return order or operand spelling. */
	public function requireReturn(expression:HxExpr):TypedBackendReturnOccurrence {
		assertCurrent(owner, revision);
		for (entry in returns)
			if (entry.expression == expression) {
				entry.assertCurrent(owner, revision);
				return entry;
			}
		throw "return is absent from this exact lambda projection";
	}

	public function getReturnTypes():Array<TyType>
		return returnTypes.copy();

	/** Reject a different owner, replaced body, or mutation after projection. */
	public function assertCurrent(owner:String, revision:String):Void {
		if (owner != this.owner || revision != this.revision)
			throw "lambda occurrence belongs to another executable or revision";
		switch expression {
			case ELambda(_, value) if (value == body):
			case _:
				throw "lambda occurrence body was replaced";
		}
		if (TypedBodyFingerprint.exactExpression(expression) != fingerprint)
			throw "lambda occurrence changed after projection";
	}
}
