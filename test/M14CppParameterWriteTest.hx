import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Prove parameter writes preserve call-local values, captured cells, and exact primitive transport. */
class M14CppParameterWriteTest {
	static function execute(command:String, arguments:Array<String>):Void {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != "" || stderr != "")
			throw "parameter write assertions failed: " + stdout + stderr;
	}

	/** Observe finite Float copies through the existing typed ABI without adding Float comparison lowering. */
	static function floatTransport(root:String):Void {
		final path = root + "/FloatTransport.hx";
		final resolved = new ResolvedModule("FloatTransport", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final index = TyperIndex.build([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index);
		final program = new backend.cpp.CppTypedProgramProjection(new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules([typed], index), false));
		final classes = new backend.cpp.CppManagedClassStorage(program);
		final owner = program.requireClass(program.requireClassIdentity("FloatTransport"));
		final inputs:Array<backend.cpp.CppManagedProgramEmitter.CppManagedProgramFunction> = [
			for (projection in owner.getFunctions()) {
				final name = projection.requireSemanticDeclaration().getSignature().getName();
				{projection: projection, rootSymbol: "generated_" + name, symbolPrefix: "hxhx_function_" + name};
			}
		];
		final body = new backend.cpp.CppManagedProgramEmitter({
			functions: inputs,
			output: [],
			classes: classes,
			casts: classes.casts,
			defaultValue: type -> backend.cpp.CppManagedStaticDefault.render(program, type)
		}).render();
		final output = ".tmp/cpp-parameter-float";
		sys.FileSystem.createDirectory(output);
		new backend.cpp.CppManagedRuntime().publish(output);
		sys.io.File.saveContent(output
			+ "/Generated.hpp", '#include "ManagedCallable.hpp"\n#include "ManagedThrow.hpp"\n'
			+ classes.render()
			+ "\n"
			+ body);
		program.assertCurrent();
		CppManagedAssertionFixture.sanitizers(output, "CPP_PARAMETER_FLOAT", "test/cpp_managed_heap/ParameterWriteObserver.cpp", "Generated.hpp");
	}

	static function main():Void {
		final root = "test/oracle/cpp_parameter_write_seed";
		execute("haxe", ["-cp", root, "-main", "Oracle", "--interp"]);
		final path = root + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final index = TyperIndex.build([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index);
		final revisions = [
			for (owner in typed.getTypedClasses())
				for (fn in owner.getFunctions())
					CompilerTypedTreeRevision.functionBody(fn)
		];
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules([typed], index), false);
		final result = CppTargetCore.emit(program, new BackendContext(".tmp/cpp-parameter-write", null, "Main", true, new haxe.ds.StringMap()));
		if (!result.builtExecutable)
			throw "parameter write fixture did not build";
		execute(result.entryPath, []);
		final after = [
			for (owner in typed.getTypedClasses())
				for (fn in owner.getFunctions())
					CompilerTypedTreeRevision.functionBody(fn)
		];
		if (revisions.join("\n") != after.join("\n"))
			throw "parameter write emission changed authored source";
		CppManagedAssertionFixture.sanitizers(".tmp/cpp-parameter-write", "CPP_PARAMETER_WRITE");
		floatTransport(root);
		Sys.println("CPP_PARAMETER_WRITE:PASS");
	}
}
