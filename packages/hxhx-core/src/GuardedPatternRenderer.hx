import TypedGuardedPatternPlan;

/** A case binding reads an immutable observation before the target creates its own local storage. */
typedef RenderedPatternCapture = {
	final source:HxSwitchPattern;
	final value:String;
}

/** Target callbacks spell primitives and lexical scopes; the shared plan selects their order. */
typedef GuardedPatternRenderServices = {
	final fresh:Void->String;
	final empty:String;
	final nullAccess:String;
	final test:(String, GuardedPatternTest) -> String;
	final read:(GuardedPatternRead, Int->String) -> String;
	final observe:(String, String, String) -> String;
	final branch:(String, String, String) -> String;
	final attempt:(Int, Array<RenderedPatternCapture>, String) -> String;
}

/** Render an already validated plan without reselecting patterns or introducing a function or loop. */
function render(plan:TypedGuardedPatternPlan, input:String, services:GuardedPatternRenderServices):String {
	plan.getSemanticKey();
	final columns = plan.getColumns();
	final names = [for (_ in columns) services.fresh()];
	function value(index:Int):String {
		if (index < 0 || index >= names.length)
			throw "guarded decision references an absent observation";
		return names[index];
	}
	function node(decision:GuardedPatternDecision):String {
		return switch decision {
			case Exhausted: services.empty;
			case NullAccess: services.nullAccess;
			case Test(column, test, yes, no): services.branch(services.test(value(column), test), node(yes), node(no));
			case Read(reads, next):
				var body = node(next);
				for (offset in 0...reads.length) {
					final index = reads[reads.length - offset - 1];
					body = services.observe(value(index), services.read(columns[index], value), body);
				}
				body;
			case Attempt(index, captures, rejected):
				services.attempt(index, [for (capture in captures) {source: capture.source, value: value(capture.column)}], node(rejected));
		};
	}
	return services.observe(names[0], input, node(plan.getRoot()));
}
