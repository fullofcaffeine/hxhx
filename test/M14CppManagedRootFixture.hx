import backend.cpp.CppManagedFunctionEmitter;

/** Native expectations are independent; production code supplies complete function units. */
function append(declarations:Array<String>):Void {
	final cases = [
		{
			source: "class Main { static function make(value:Dynamic, spare:Dynamic):Bool->Dynamic { return function(choose:Bool):Dynamic { if (choose) return value; return spare; }; } }",
			symbol: "generatedRootParameterCreator"
		},
		{
			source: "class Main { static function pick(flag:Bool, value:Int):Int { if (flag) { var copy = value; return copy; } return 7; } }",
			symbol: "generatedRootBranch"
		},
		{source: "class Main { static function finish():Void { return; } }", symbol: "generatedRootVoid"}
	];
	for (entry in cases) {
		final parsed = new ResolvedModule("Main", "Main.hx", ParserStage.parse(entry.source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed])).getTypedClasses()[0].getFunctions()[0];
		final revision = CompilerTypedTreeRevision.functionBody(typed);
		final emitter = new CppManagedFunctionEmitter({
			projection: TypedBodySource.functionProjection(typed),
			rootSymbol: entry.symbol,
			symbolPrefix: "hxhx_function_" + entry.symbol
		});
		final rendered = emitter.render();
		if (rendered != emitter.render())
			throw "root unit emission is not deterministic";
		declarations.push(rendered);
		if (revision != CompilerTypedTreeRevision.functionBody(typed))
			throw "root unit emission mutated authored typing";
	}
}
