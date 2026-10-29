import backend.BackendContext;
import backend.BackendRegistry;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Builds and executes the repo-owned `Int % Int64` contract through C++. **/
class M14CppIntModInt64IntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
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

	/** Operator lowering must select the authored provider instead of a synthetic native carrier. */
	static function assertProvider(program:MacroExpandedProgram):Void {
		var provider = false;
		var moduloCalls = 0;
		var mixedRemainders = 0;
		function expression(value:TypedExpr):Void {
			final declaration = value.getDeclaration();
			if (value.getTag() == Call && declaration != null && declaration.getOwner().getCanonicalName() == "haxe.Int64")
				switch declaration.getSignature().getName() {
					case "mod":
						moduloCalls++;
					case "intMod":
						mixedRemainders++;
					case _:
				}
			for (child in value.getExpressions())
				expression(child);
		}
		function statement(value:TypedStmt):Void {
			for (child in value.getExpressions())
				expression(child);
			for (child in value.getStatements())
				statement(child);
		}
		for (module in program.getTypedModules()) {
			final name = module.getSourceOrigin().sourceModulePath;
			if (name == "haxe.Int64")
				provider = new CompilerSourceProvider().isFile(module.getParsed().getFilePath());
			if (name == "Main" || name == "Contract")
				for (owner in module.getTypedClasses())
					for (fn in owner.getFunctions())
						for (body in fn.getBody().getStatements())
							statement(body);
		}
		assertTrue(provider && moduloCalls == 14 && mixedRemainders == 0,
			"Int64 modulo lost its real provider or selected calls: provider="
			+ provider
			+ ", mod="
			+ moduloCalls
			+ ", intMod="
			+ mixedRemainders);
	}

	/** Compare every output case under both sanitizer optimizations and forced collection. */
	static function sanitizers(root:String, expected:String):Void {
		File.copy("test/cpp_managed_heap/Int64OutputObserver.cpp", root + "/Observer.cpp");
		final compiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		for (optimization in ["-O0", "-O2"]) {
			final executable = root + "/observer" + optimization;
			assertTrue(Sys.command(timeout, [
				"90",
				compiler,
				"-std=c++17",
				optimization,
				"-g",
				"-fno-omit-frame-pointer",
				"-fsanitize=address,undefined",
				"-fno-sanitize-recover=all",
				'-DHXHX_LOCAL_PROGRAM="src/Contract.cpp"',
				root + "/Observer.cpp",
				"-o",
				executable
			]) == 0, "Int64 sanitizer compilation failed");
			final observed = commandOutput(timeout, ["30", executable]);
			assertTrue(observed.code == 0 && observed.stdout == expected && observed.stderr == "",
				"Int64 sanitizer behavior differs: " + observed.stdout + observed.stderr);
			Sys.println("CPP_INT_MOD_INT64:" + optimization + ":PASS");
		}
	}

	/** Validate an emitted artifact without changing its generated source. */
	static function validateArtifact(root:String, entryPath:String, expected:String):Void {
		final generated = File.getContent(Path.join([root, "src", "Contract.cpp"]));
		assertTrue(generated.indexOf("Int64::intMod") < 0, "C++ emitted an unbound Int64.intMod class helper");
		assertTrue(generated.indexOf("Int64::mod(") < 0, "C++ emitted an unbound Int64 class helper");
		assertTrue(generated.indexOf("__hxhx_int64_mod(") < 0, "C++ bypassed the authored Int64 provider with a legacy carrier helper");
		final executed = commandOutput(entryPath);
		assertTrue(executed.code == 0 && executed.stderr == "", "focused Int % Int64 executable failed: " + executed.stderr);
		assertTrue(executed.stdout == expected, "unexpected focused Int % Int64 stdout:\n" + executed.stdout);
		sanitizers(root, expected);
	}

	static function main():Void {
		final expected = File.getContent("test/oracle/cpp_int_mod_int64_seed/expected.stdout");
		final upstream = commandOutput("haxe", ["-cp", "test/oracle/cpp_int_mod_int64_seed/src", "-main", "Contract", "--interp"]);
		assertTrue(upstream.code == 0 && upstream.stdout == expected && upstream.stderr == "", "upstream Int64 modulo contract differs");
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/oracle/cpp_int_mod_int64_seed/src",
			mainModule: "Contract",
			requiredModules: ["Main", "haxe.Int64", "Sys"]
		});
		final revisions = [
			for (module in fixture.modules)
				for (owner in module.getTypedClasses())
					for (fn in owner.getFunctions())
						CompilerTypedTreeRevision.functionBody(fn)
		];
		final program = CppResolvedFixture.prepare(fixture);
		assertProvider(program);

		final root = Path.join([Sys.getCwd(), ".tmp", "m14_cpp_int_mod_int64"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		final context = new BackendContext(root, null, "Contract", true, fixture.defines);
		final result = BackendRegistry.createForTarget("cpp-native").emit(program, context);
		assertTrue(result.builtExecutable, "focused Int % Int64 C++ artifact did not build");

		validateArtifact(root, result.entryPath, expected);
		final after = [
			for (module in fixture.modules)
				for (owner in module.getTypedClasses())
					for (fn in owner.getFunctions())
						CompilerTypedTreeRevision.functionBody(fn)
		];
		assertTrue(revisions.join("\n") == after.join("\n"), "Int64 preparation or emission changed the authored source");
		program.assertTypedBodyRevisionsCurrent();
		deleteRecursive(root);
		Sys.println("CPP_INT_MOD_INT64:PASS");
	}
}
