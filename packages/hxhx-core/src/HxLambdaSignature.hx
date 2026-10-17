/** Source facts for one parameter; omitted type syntax remains absent. */
typedef HxLambdaParameter = {
	final ?typeHint:String;
	final isOptional:Bool;
	final isRest:Bool;
	final hasDefault:Bool;
}

/**
 * Preserves the annotations written on a function expression independently of its inferred type.
 * Authored functions keep default expressions as separate children. This value records declaration facts only.
 */
class HxLambdaSignature {
	final parameters:Array<HxLambdaParameter>;
	final returnTypeHint:Null<String>;

	public function new(parameters:Array<HxLambdaParameter>, ?returnTypeHint:String) {
		this.parameters = [for (parameter in parameters) copyParameter(parameter)];
		this.returnTypeHint = returnTypeHint;
	}

	static function copyParameter(parameter:HxLambdaParameter):HxLambdaParameter {
		return {
			typeHint: parameter.typeHint,
			isOptional: parameter.isOptional,
			isRest: parameter.isRest,
			hasDefault: parameter.hasDefault
		};
	}

	public function getParameters():Array<HxLambdaParameter>
		return [for (parameter in parameters) copyParameter(parameter)];

	public function getReturnTypeHint():Null<String>
		return returnTypeHint;

	/** Includes annotation absence so annotation-only changes invalidate source and typed revisions. */
	public function getCanonicalIdentity():String {
		final facts:Array<Null<String>> = [returnTypeHint, Std.string(parameters.length)];
		for (parameter in parameters) {
			facts.push(parameter.typeHint);
			facts.push(parameter.isOptional ? "optional" : "required");
			facts.push(parameter.isRest ? "rest" : "single");
			facts.push(parameter.hasDefault ? "default" : "no-default");
		}
		return CompilerCacheIdentity.encode(facts);
	}
}
