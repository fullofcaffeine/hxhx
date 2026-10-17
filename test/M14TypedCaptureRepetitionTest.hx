/** Repeated declarations need fresh capture storage; a nested invocation starts its own scope. */
class M14TypedCaptureRepetitionTest {
	static function check(plan:TypedCapturePlan, name:String, repeated:Bool):Void {
		final matches = plan.getBindings().filter(fact -> fact.binding.getSourceName() == name);
		if (matches.length != 1 || matches[0].isRepeated != repeated)
			throw "capture repetition differs for " + name + ": expected " + repeated;
	}

	public static function run():Void {
		final source = "class Main { static function make():Void {"
			+ "var once = 2; while ({ var conditionLocal = once; once--; conditionLocal > 0; }) {"
			+ "var bodyLocal = once; var factory = function(seed:Int):Void->Int { var invocationLocal = seed; return () -> invocationLocal; };"
			+ "var reader = () -> bodyLocal; }"
			+ "for (index in 0...2) { var rangeLocal = index; var readRange = () -> rangeLocal; }"
			+ "do { var doLocal = once; once++; } while (once < 1);"
			+ "var selected = [for (item in [1,2]) { var elementLocal = item; () -> elementLocal; }];"
			+ "} }";
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final fn = TyperStage.typeResolvedModule(module, TyperIndex.build([module])).getTypedClasses()[0].getFunctions()[0];
		for (plan in [
			TypedCapturePlan.analyze(fn),
			TypedCapturePlan.afterLowering(fn, TypedControlLowering.functionBody(fn))
		]) {
			for (name in ["once", "seed", "invocationLocal", "selected"])
				check(plan, name, false);
			for (name in [
				"conditionLocal",
				"bodyLocal",
				"factory",
				"reader",
				"index",
				"rangeLocal",
				"readRange",
				"doLocal",
				"item",
				"elementLocal"
			])
				check(plan, name, true);
		}
		Sys.println("TYPED_CAPTURE_REPETITION:PASS");
	}
}
