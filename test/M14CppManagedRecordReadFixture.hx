import backend.cpp.CppManagedFunctionEmitter;

/** Primitive-only function contracts exercise authored record selection without fabricated provider types. */
function append(declarations:Array<String>):Void {
	final path = "test/oracle/cpp_managed_record_read_seed/src/Main.hx";
	final parsed = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
	final typed = TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed]));
	var count = 0;
	for (fn in typed.getTypedClasses()[0].getFunctions()) {
		final name = HxFunctionDecl.getName(fn.getSourceDeclaration());
		if (name == "main")
			continue;
		final emitter = new CppManagedFunctionEmitter({
			projection: TypedBodySource.functionProjection(fn),
			rootSymbol: "generatedRecord" + name,
			symbolPrefix: "hxhx_function_record" + name
		});
		declarations.push(emitter.render());
		count++;
	}
	if (count != 5)
		throw "record fixture lost an authored function";
}
