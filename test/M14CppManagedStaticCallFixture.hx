import backend.cpp.CppManagedProgramEmitter;

/** Program-selected methods call later declarations through the production argument sequencer. */
function append(declarations:Array<String>):Void {
	final source = "class Main { static function entry():Int { var counter = make(); var first = counter(2); return first - counter(1); } static function make():Int->Int { var calls = 0; function count(n:Int):Int { calls++; return n == 0 ? calls : count(n-1); } return count; } static function ordered(effect:Void->Int):Int { return combine(effect(), effect()); } static function combine(left:Int, right:Int):Int { return left - right; } static function relay(value:Dynamic):Dynamic { return identity(value); } static function identity(value:Dynamic):Dynamic { return value; } static function run(effect:Void->Void):Void { side(effect); } static function side(effect:Void->Void):Void { effect(); } static function deferred(value:Int):Void->Int { return function():Int { return combine(value, 1); }; } static function owners():Int { return Left.pick() - Right.pick(); } } class Left { public static function pick():Int { return 11; } } class Right { public static function pick():Int { return 4; } }";
	final parsed = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
	final functions:Array<TypedFunction> = [];
	for (cls in TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed])).getTypedClasses())
		for (fn in cls.getFunctions())
			functions.push(fn);
	final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
	final emitter = new CppManagedProgramEmitter({
		output: [],
		functions: [
			for (index in 0...functions.length)
				{
					projection: TypedBodySource.functionProjection(functions[index]),
					rootSymbol: "generatedStatic" + StringTools.replace(functions[index].getOwnerName(), ".",
						"_") + HxFunctionDecl.getName(functions[index].getSourceDeclaration()),
					symbolPrefix: "hxhx_function_static" + index
				}
		]
	});
	final rendered = emitter.render();
	if (rendered != emitter.render())
		throw "static program emission is not deterministic";
	declarations.push(rendered);
	for (index in 0...functions.length)
		if (revisions[index] != CompilerTypedTreeRevision.functionBody(functions[index]))
			throw "static program emission mutated authored typing";
}
