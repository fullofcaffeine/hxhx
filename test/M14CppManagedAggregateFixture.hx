import backend.cpp.CppManagedFunctionEmitter;

/** Real provider types feed production aggregate emission; native code observes lifetime independently. */
function append(declarations:Array<String>):Void {
	final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/cpp_managed_aggregate_seed/src", mainModule: "Main", requiredModules: ["Array"]});
	final selected = ["records", "mixed", "ordered", "empty", "strings"];
	var count = 0;
	for (typed in fixture.main.getTypedClasses()[0].getFunctions()) {
		final name = HxFunctionDecl.getName(typed.getSourceDeclaration());
		if (selected.indexOf(name) < 0)
			continue;
		final revision = CompilerTypedTreeRevision.functionBody(typed);
		final emitter = new CppManagedFunctionEmitter({
			projection: TypedBodySource.functionProjection(typed),
			rootSymbol: "generatedAggregate" + name,
			symbolPrefix: "hxhx_function_aggregate" + name
		});
		final first = emitter.render();
		if (first != emitter.render() || revision != CompilerTypedTreeRevision.functionBody(typed))
			throw "aggregate emission changed its typed source or deterministic output";
		declarations.push(first);
		count++;
	}
	if (count != selected.length)
		throw "aggregate fixture lost an authored function";
}
