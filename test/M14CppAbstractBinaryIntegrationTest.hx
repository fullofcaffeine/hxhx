import backend.BackendContext;
import backend.BackendRegistry;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Builds and executes the repo-owned abstract-binary contract through C++. **/
class M14CppAbstractBinaryIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertContains(content:String, needle:String, message:String):Void {
		assertTrue(content.indexOf(needle) >= 0, message + " (missing `" + needle + "`)");
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function commandOutput(command:String, ?arguments:Array<String>):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, arguments == null ? [] : arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	static function main():Void {
		final sourceRoot = "test/oracle/cpp_abstract_binary_operator_seed/src";
		final expected = File.getContent("test/oracle/cpp_abstract_binary_operator_seed/expected.stdout");
		final upstream = commandOutput("haxe", ["-cp", sourceRoot, "--run", "Main"]);
		assertTrue(upstream.code == 0 && upstream.stderr == "" && upstream.stdout == expected,
			"upstream abstract-binary contract differs: " + upstream.stdout + upstream.stderr);
		Sys.println("CPP_ABSTRACT_BINARY:UPSTREAM:PASS");
		// Calls and output conversions need their real declarations. Production
		// preparation also preserves the exact selected operator and source effects.
		final fixture = CppResolvedFixture.load({sourceRoot: sourceRoot, mainModule: "Main", requiredModules: ["Std", "Sys", "Array"]});
		final revisions = [
			for (module in fixture.modules)
				CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity()
		];
		Sys.println("CPP_ABSTRACT_BINARY:LOADED modules=" + fixture.modules.length);
		final program = CppResolvedFixture.prepare(fixture);
		Sys.println("CPP_ABSTRACT_BINARY:PREPARED");

		final root = Path.join([Sys.getCwd(), ".tmp", "m14_cpp_abstract_binary"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		final context = new BackendContext(root, null, "Main", true, true, fixture.defines);
		final result = BackendRegistry.createForTarget("cpp-native").emit(program, context);
		assertTrue(result.builtExecutable, "focused abstract-binary C++ artifact did not build");
		for (index in 0...fixture.modules.length)
			assertTrue(revisions[index] == CompilerTypedModuleRevision.fromTypedModule(fixture.modules[index]).getCanonicalIdentity(),
				"abstract-binary preparation changed an authored typed module");
		final generated = File.getContent(Path.join([root, "src", "Main.cpp"]));
		for (helper in [
			"Ticket::mergeArbitrarily",
			"Ticket::decorateArbitrarily",
			"Ticket::trimArbitrarily",
			"Ticket::advanceArbitrarily",
			"Parcel::uniteArbitrarily",
			"Parcel::enlargeArbitrarily",
			"Parcel::enlargeInPlaceArbitrarily",
			"Distance::reduceArbitrarily",
			"Distance::labelArbitrarily",
			"FallbackDistance::addArbitrarily"
		])
			assertContains(generated, helper, "C++ lost the exact arbitrary-name declaration selected by the shared typer");
		assertContains(generated, "__hxhx_abstract_binary_left_", "C++ did not receive source-order binary temporaries");
		assertContains(generated, "auto&& __hxhx_abstract_binary_array_",
			"C++ copied an indexed Haxe Array temporary and detached shared writeback from the original place");
		assertContains(generated, "__hxhx_abstract_value", "class-backed abstract wrapper did not retain its exact underlying object");
		assertTrue(generated.indexOf("mutateArbitrarily(") < 0, "inline instance compound helper survived for C++ reinterpretation");
		assertTrue(generated.indexOf("__hxhx_Parcel_underlying") < 0, "C++ reconstructed a class-backed result by copying underlying fields");

		final cppCore = File.getContent("packages/hxhx-core/src/backend/cpp/CppTargetCore.hx");
		for (legacyOwner in [
			"primitiveStringAbstractBinaryOpExpr",
			"classBackedAbstractBinaryOpMethod",
			"isPrimitiveStringRepeatHelper"
		])
			assertTrue(cppCore.indexOf(legacyOwner) < 0, "legacy target-side abstract binary owner survived: " + legacyOwner);

		final executed = commandOutput(result.entryPath);
		assertTrue(executed.code == 0, "focused abstract-binary executable failed: " + executed.stderr);
		assertTrue(executed.stdout == expected, "unexpected focused abstract-binary stdout:\n" + executed.stdout);
		Sys.println("CPP_ABSTRACT_BINARY:PASS");
		deleteRecursive(root);
	}
}
