import backend.cpp.CppManagedProgramEmitter;
import backend.cpp.CppManagedRuntime;

/** Real Sys declarations drive emission; a separate native observer checks exact output bytes. */
function verify(directory:String, compiler:String, timeout:String):Void {
	final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/cpp_managed_output_seed/src", mainModule: "Main", requiredModules: ["Sys"]});
	final provider = fixture.index.getByFullName("Sys");
	if (provider == null)
		throw "output fixture lost its real Sys provider";
	final output = [
		for (declaration in provider.getDeclarations())
			if (declaration.getSignature().getName() == "print" || declaration.getSignature().getName() == "println") declaration
	];
	if (output.length != 2)
		throw "output fixture requires both exact standard declarations";
	final functions = fixture.main.getTypedClasses()[0].getFunctions();
	final inputs:Array<backend.cpp.CppManagedProgramEmitter.CppManagedProgramFunction> = [];
	var unsupported:Null<TypedFunction> = null;
	for (fn in functions) {
		final name = HxFunctionDecl.getName(fn.getSourceDeclaration());
		if (name == "unsupported")
			unsupported = fn;
		if (["values", "effect", "text", "deferred", "erased", "erasedEffect"].indexOf(name) >= 0)
			inputs.push({
				projection: TypedBodySource.functionProjection(fn),
				rootSymbol: "generatedOutput" + name,
				symbolPrefix: "hxhx_function_output" + name
			});
	}
	if (inputs.length != 6 || unsupported == null)
		throw "output fixture lost an authored function";
	final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
	final emitter = new CppManagedProgramEmitter({functions: inputs, output: output});
	final rendered = emitter.render();
	if (rendered != emitter.render())
		throw "output emission is not deterministic";
	for (index in 0...functions.length)
		if (revisions[index] != CompilerTypedTreeRevision.functionBody(functions[index]))
			throw "output emission mutated typed source";
	rejected(() -> new CppManagedProgramEmitter({functions: inputs, output: []}).render(), "lacks the selected static declaration");
	rejected(() -> new CppManagedProgramEmitter({functions: inputs, output: [output[0], output[0]]}), "repeats a declaration identity");
	rejected(() -> new CppManagedProgramEmitter({
		functions: [
			{projection: TypedBodySource.functionProjection(unsupported), rootSymbol: "unsupported", symbolPrefix: "hxhx_function_unsupported"}
		],
		output: output
	}).render(), "supported exact value formatting contract");
	final wrongOwner = fixture.main.getTypedClasses()[1].getFunctions()[0].getDeclaration();
	rejected(() -> backend.cpp.CppManagedOutput.requireDeclaration(wrongOwner), "exact Sys declaration");
	final signature = output[0].getSignature();
	signature.getArgOptional()[0] = true;
	rejected(() -> emitter.render(), "exact Sys output signature");
	signature.getArgOptional()[0] = false;
	if (emitter.render() != rendered)
		throw "output declaration restoration changed emission";
	sys.FileSystem.createDirectory(directory);
	new CppManagedRuntime().publish(directory + "/runtime");
	sys.io.File.saveContent(directory + "/Output.generated.hpp", '#pragma once\n#include "ManagedCallable.hpp"\n#include "ManagedOutput.hpp"\n' + rendered);
	sys.io.File.copy("test/cpp_managed_heap/GeneratedOutputTest.cpp", directory + "/GeneratedOutputTest.cpp");
	final expected = sys.io.File.getBytes("test/oracle/cpp_managed_output_seed/expected.stdout");
	for (optimization in ["-O0", "-O2"]) {
		final executable = directory + "/test" + optimization;
		if (Sys.command(timeout, [
			"60",
			compiler,
			"-std=c++17",
			"-Wall",
			"-Wextra",
			"-Werror",
			optimization,
			"-g",
			"-fno-omit-frame-pointer",
			"-fsanitize=address,undefined",
			"-I",
			directory + "/runtime",
			"-I",
			directory,
			directory + "/GeneratedOutputTest.cpp",
			"-o",
			executable
		]) != 0)
			throw "managed output native observer did not compile";
		final process = new sys.io.Process(timeout, ["60", executable]);
		final stdout = process.stdout.readAll();
		final stderr = process.stderr.readAll().toString();
		final result = process.exitCode();
		process.close();
		if (result != 0 || stdout.compare(expected) != 0 || stderr.length != 0)
			throw "managed output changed native behavior: " + stdout.toHex() + " " + stderr;
	}
	Sys.println("CPP_MANAGED_OUTPUT:PASS");
}

/** Require the intended boundary to reject the case, not an unrelated earlier failure. */
private function rejected(run:Void->Void, message:String):Void {
	try {
		run();
	} catch (failure:haxe.Exception) {
		if (failure.message.indexOf(message) >= 0)
			return;
		throw failure;
	}
	throw "output fixture accepted invalid input: " + message;
}
