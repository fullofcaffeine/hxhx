import backend.cpp.CppManagedProgramEmitter;

/** Emit the unchanged escaping-counter acceptance source with real standard-library providers. */
function append(declarations:Array<String>):Void {
	final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/source_named_function_seed/src", mainModule: "Main", requiredModules: ["Array", "Sys"]});
	final provider = fixture.index.getByFullName("Sys");
	if (provider == null)
		throw "original program lost its Sys provider";
	final output = [
		for (declaration in provider.getDeclarations())
			if (["print", "println"].indexOf(declaration.getSignature().getName()) >= 0) declaration
	];
	final functions = fixture.main.getTypedClasses()[0].getFunctions();
	final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
	final emitter = new CppManagedProgramEmitter({
		output: output,
		functions: [
			for (fn in functions)
				{
					projection: TypedBodySource.functionProjection(fn),
					rootSymbol: "generatedOriginal" + HxFunctionDecl.getName(fn.getSourceDeclaration()),
					symbolPrefix: "hxhx_function_original" + HxFunctionDecl.getName(fn.getSourceDeclaration())
				}
		]
	});
	final rendered = emitter.render();
	if (rendered != emitter.render())
		throw "original program emission is not deterministic";
	for (index in 0...functions.length)
		if (revisions[index] != CompilerTypedTreeRevision.functionBody(functions[index]))
			throw "original program emission changed its typed source";
	declarations.push('#include "ManagedOutput.hpp"');
	declarations.push(rendered);
}

/** Check complete source output and sanitizer exit status, not a simplified counter substitute. */
function observe(executable:String, timeout:String):Void {
	final process = new sys.io.Process(timeout, ["60", executable, "original"]);
	final stdout = process.stdout.readAll();
	final stderr = process.stderr.readAll().toString();
	final code = process.exitCode();
	process.close();
	if (code != 0
		|| stderr.length != 0
		|| stdout.compare(sys.io.File.getBytes("test/oracle/source_named_function_seed/expected.stdout")) != 0)
		throw "original managed counter changed runtime behavior: " + stdout.toString() + stderr;
	Sys.println("CPP_MANAGED_ORIGINAL_COUNTER:PASS");
}
