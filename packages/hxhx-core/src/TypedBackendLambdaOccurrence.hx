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

	public function new(input:{
		owner:String,
		revision:String,
		source:TypedExpr,
		expression:HxExpr
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
		collectReturns(input.source.getExpressions()[0]);
		fingerprint = TypedBodyFingerprint.exactExpression(expression);
	}

	/** Nested lambdas own their returns; only this function's exits enter the contract. */
	function collectReturns(value:TypedExpr):Void {
		if (value.getTag() == Lambda)
			return;
		if (value.getTag() == ReturnExpr) {
			final values = value.getExpressions();
			returnTypes.push(values.length == 0 ? TyType.fromHintText("Void") : values[0].getType());
		}
		for (child in value.getExpressions())
			collectReturns(child);
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
