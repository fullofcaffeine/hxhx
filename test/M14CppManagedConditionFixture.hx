import backend.cpp.CppManagedFunctionEmitter;

/** Collecting conditions execute at the source branch/loop test, never at function entry. */
function append(declarations:Array<String>):Void {
	final source = "class Main { static function branch(effect:Void->Bool):Int { if (effect()) return 1; return 2; } static function loop(effect:Void->Bool):Int { var run = function():Int { var count = 0; while (effect()) { count++; } return count; }; return run(); } static function doLoop(effect:Void->Bool):Int { var run = function():Int { var count = 0; do { count++; } while (effect()); return count; }; return run(); } }";
	final parsed = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
	final functions = TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed])).getTypedClasses()[0].getFunctions();
	for (index in 0...functions.length) {
		final typed = functions[index];
		final revision = CompilerTypedTreeRevision.functionBody(typed);
		final emitter = new CppManagedFunctionEmitter({
			projection: TypedBodySource.functionProjection(typed),
			rootSymbol: "generatedCondition" + HxFunctionDecl.getName(typed.getSourceDeclaration()),
			symbolPrefix: "hxhx_function_condition" + index
		});
		declarations.push(emitter.render());
		if (revision != CompilerTypedTreeRevision.functionBody(typed))
			throw "condition emission mutated authored typing";
	}
}
