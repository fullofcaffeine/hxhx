/** The function syntax that macros observe before type inference or lowering. */
enum HxSourceFunctionKind {
	Anonymous;
	Named(name:String, isInline:Bool);
	Arrow;
}

/** Retain statement versus value placement; named functions introduce a local in either position. */
enum HxSourceFunctionPlacement {
	Value;
	Declaration;
}

/** Written signature facts supplied by the parser for one function. */
typedef HxSourceFunctionInput = {
	final kind:HxSourceFunctionKind;
	final placement:HxSourceFunctionPlacement;
	final arguments:Array<String>;
	final signature:HxLambdaSignature;
	final ?generics:HxSourceFunctionGenerics;
}

/**
	Preserves written function syntax independently of its selected callable type.

	The enclosing expression owns the body and default expressions as recursive
	children. This value owns signature syntax without expression children, which avoids an OCaml module cycle.
	Default children follow parameter order; their indexes never imply an optional marker.
 */
class HxSourceFunction {
	final kind:HxSourceFunctionKind;
	final placement:HxSourceFunctionPlacement;
	final arguments:Array<String>;
	final signature:HxLambdaSignature;
	final defaultParameterIndexes:Array<Int>;
	final generics:HxSourceFunctionGenerics;

	public function new(input:HxSourceFunctionInput) {
		if (input.signature == null || input.arguments.length != input.signature.getParameters().length)
			throw "source function parameter facts differ from its arguments";
		switch [input.kind, input.placement] {
			case [Named(name, _), _]:
				if (name.length == 0)
					throw "named source function requires a name";
			case [_, Declaration]:
				throw "source function declaration requires a named function";
			case [_, Value]:
		}
		this.kind = input.kind;
		this.placement = input.placement;
		this.arguments = input.arguments.copy();
		this.signature = input.signature;
		this.generics = input.generics == null ? HxSourceFunctionGenerics.empty() : input.generics;
		this.defaultParameterIndexes = [];
		final parameters = signature.getParameters();
		for (index in 0...parameters.length)
			if (parameters[index].hasDefault)
				defaultParameterIndexes.push(index);
	}

	public function getKind():HxSourceFunctionKind
		return kind;

	public function getPlacement():HxSourceFunctionPlacement
		return placement;

	public function getArguments():Array<String>
		return arguments.copy();

	/** Named function values also introduce this name in the surrounding lexical scope. */
	public function getDeclaredName():Null<String>
		return switch kind {
			case Named(name, _): name;
			case _: null;
		};

	/** The declared name precedes parameter identities in typing and typed-body replay. */
	public function getBindingNames():Array<String> {
		final name = getDeclaredName();
		return name == null ? arguments.copy() : [name].concat(arguments);
	}

	public function getSignature():HxLambdaSignature
		return signature;

	public function getGenerics():HxSourceFunctionGenerics
		return generics;

	public function getDefaultParameterIndexes():Array<Int>
		return defaultParameterIndexes.copy();

	/** Validate the recursive child layout at construction and immutable rebuild boundaries. */
	public function assertDefaultCount(count:Int):Void {
		if (count != defaultParameterIndexes.length)
			throw "source function default children differ from its parameter facts";
	}

	/** Syntax-only changes must invalidate both source fingerprints and typed revisions. */
	public function getCanonicalIdentity():String {
		final facts:Array<Null<String>> = [
			"source-function-v3",
			signature.getCanonicalIdentity(),
			generics.getCanonicalIdentity()
		];
		switch kind {
			case Anonymous:
				facts.push("anonymous");
			case Named(name, isInline):
				facts.push("named");
				facts.push(name);
				facts.push(isInline ? "inline" : "ordinary");
			case Arrow:
				facts.push("arrow");
		}
		facts.push(switch placement {
			case Value: "value";
			case Declaration: "declaration";
		});
		for (argument in arguments)
			facts.push(argument);
		return CompilerCacheIdentity.encode(facts);
	}
}
