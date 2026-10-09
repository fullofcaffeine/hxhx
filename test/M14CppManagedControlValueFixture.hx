import backend.cpp.CppManagedFunctionEmitter;

/** Use unchanged source methods for branch-result storage and scalar switch observation. */
function append(declarations:Array<String>):Void {
	final path = "test/oracle/cpp_managed_control_value_seed/src/Main.hx";
	final parsed = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
	final functions = TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed])).getTypedClasses()[0].getFunctions();
	var count = 0;
	for (typed in functions) {
		final name = HxFunctionDecl.getName(typed.getSourceDeclaration());
		if (name == "main")
			continue;
		final revision = CompilerTypedTreeRevision.functionBody(typed);
		final emitter = new CppManagedFunctionEmitter({
			projection: TypedBodySource.functionProjection(typed),
			rootSymbol: "generatedControlValue" + name,
			symbolPrefix: "hxhx_function_controlvalue" + name
		});
		final emitted = emitter.render();
		if (emitted != emitter.render() || revision != CompilerTypedTreeRevision.functionBody(typed))
			throw "control-value emission changed authored typing or output";
		declarations.push(emitted);
		count++;
	}
	if (count != 8)
		throw "control-value fixture lost an authored method";
}
