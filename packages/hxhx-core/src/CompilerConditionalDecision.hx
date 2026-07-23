/** One evaluated conditional expression and the definition inputs it actually read. **/
class CompilerConditionalDecision {
	final expressionRevision:String;
	final result:Bool;
	final inputs:Array<CompilerConditionalDefineInput>;
	final canonicalIdentity:String;

	public function new(expressionRevision:String, result:Bool, inputs:Array<CompilerConditionalDefineInput>) {
		this.expressionRevision = expressionRevision == null ? "" : expressionRevision;
		if (this.expressionRevision.length == 0)
			throw "conditional-compilation expression revision is required";
		this.result = result;
		this.inputs = normalizeInputs(inputs);
		final values = new Array<Null<String>>();
		values.push("conditional-decision-v1");
		values.push(this.expressionRevision);
		values.push(result ? "true" : "false");
		for (input in this.inputs)
			values.push(input.canonicalKey());
		canonicalIdentity = CompilerCacheIdentity.encode(values);
	}

	public static function fromEvaluation(expression:String, result:Bool, inputs:Array<CompilerConditionalDefineInput>):CompilerConditionalDecision {
		return new CompilerConditionalDecision(CompilerCacheIdentity.encode(["conditional-expression-v1", expression]), result, inputs);
	}

	public function getInputs():Array<CompilerConditionalDefineInput>
		return inputs.copy();

	public function getCanonicalIdentity():String
		return canonicalIdentity;

	static function normalizeInputs(values:Array<CompilerConditionalDefineInput>):Array<CompilerConditionalDefineInput> {
		final byAccess = new haxe.ds.StringMap<CompilerConditionalDefineInput>();
		if (values != null)
			for (value in values) {
				if (value == null)
					throw "conditional-compilation decision contains a null definition input";
				final accessKey = value.accessKey();
				final previous = byAccess.get(accessKey);
				if (previous != null && previous.getObservedInputRevision() != value.getObservedInputRevision())
					throw "conditional-compilation decision contains conflicting observations for definition: " + value.name;
				byAccess.set(accessKey, value);
			}
		final keys = [for (key in byAccess.keys()) key];
		keys.sort(compareText);
		return [for (key in keys) byAccess.get(key)];
	}

	static function compareText(left:String, right:String):Int
		return left < right ? -1 : (left > right ? 1 : 0);
}
