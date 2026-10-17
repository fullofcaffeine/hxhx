/** Native enum comparison retains conversion effects and upstream target-specific numeric text. */
class M14CppEnumEqualityTest {
	static function main():Void {
		final root = "test/oracle/cpp_dynamic_equality_seed/enum_payload";
		for (main in ["EnumPayloadProbe", "FloatTextProbe"]) {
			final fixture = CppResolvedFixture.load({sourceRoot: root, mainModule: main, requiredModules: ["Math", "Std"]});
			final revisions = fixture.modules.map(module -> CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity());
			final output = ".tmp/cpp-enum-equality/" + main;
			final result = backend.cpp.CppTargetCore.emit(CppResolvedFixture.prepare(fixture),
				new backend.BackendContext(output, null, main, true, true, fixture.defines));
			if (!result.builtExecutable)
				throw "enum comparison fixture did not build";
			for (index in 0...fixture.modules.length)
				if (CompilerTypedModuleRevision.fromTypedModule(fixture.modules[index]).getCanonicalIdentity() != revisions[index])
					throw "enum comparison changed authored source";
			final expected = sys.io.File.getContent(root + (main == "EnumPayloadProbe" ? "/expected.cpp.stdout" : "/float.expected.cpp.stdout"));
			execute(result.entryPath, expected);
			for (optimization in ["-O0", "-O2"]) {
				final binary = output + "/observer" + optimization;
				if (Sys.command("c++", [
					"-std=c++17",
					optimization,
					"-Wall",
					"-Wextra",
					"-Werror",
					"-g",
					"-fno-omit-frame-pointer",
					"-fsanitize=address,undefined",
					"-fno-sanitize-recover=all",
					"-I" + output + "/src",
					'-DHXHX_LOCAL_PROGRAM="' + main + '.cpp"',
					"-DENUM_SINGLETONS=" + (main == "EnumPayloadProbe" ? "1" : "0"),
					root + "/Observe.cpp",
					"-o",
					binary
				]) != 0)
					throw "enum comparison observer failed to compile";
				execute(binary, expected + expected);
				Sys.println("CPP_ENUM_EQUALITY:" + main + ":" + optimization + ":PASS");
			}
		}
	}

	/** A sanitizer report, unexpected signal, or output difference is a failed observation. */
	static function execute(binary:String, expected:String):Void {
		final child = new sys.io.Process(binary, []);
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final code = try child.exitCode() catch (failure:haxe.Exception) {
			child.close();
			throw new haxe.Exception("enum observer failed: " + stderr, failure);
		};
		child.close();
		if (code != 0 || stderr != "" || stdout != expected)
			throw "enum observer differs from upstream: " + code + " " + stderr + " output=" + stdout;
	}
}
