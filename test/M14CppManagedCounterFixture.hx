import backend.cpp.CppManagedFunctionEmitter;

/** Production code owns every entry, environment link, signature, and counter body. */
function append(declarations:Array<String>):Void {
	final path = "test/oracle/source_named_function_seed/src/Main.hx";
	final parsed = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
	final candidates = TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed]))
		.getTypedClasses()[0].getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getSourceDeclaration()) == "makeCounter");
	if (candidates.length != 1)
		throw "the unchanged original counter factory is missing";
	final typed = candidates[0];
	final revision = CompilerTypedTreeRevision.functionBody(typed);
	final emitter = new CppManagedFunctionEmitter({
		projection: TypedBodySource.functionProjection(typed),
		rootSymbol: "generatedCounterCreator",
		symbolPrefix: "hxhx_function_counter"
	});
	final rendered = emitter.render();
	if (rendered != emitter.render())
		throw "counter unit emission is not deterministic";
	declarations.push(rendered);
	if (revision != CompilerTypedTreeRevision.functionBody(typed))
		throw "counter emission mutated source typing";
}
