import backend.cpp.CppManagedProgramEmitter;
import backend.cpp.CppTypedProgramProjection;

/** Observe Float array defaults through exact authored methods and the real Array provider. */
class M14CppFloatArrayDefaultTest {
	static function main():Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/oracle/cpp_managed_array_read_seed/src",
			mainModule: "Main",
			requiredModules: ["Array"]
		});
		final program = new CppTypedProgramProjection(CppResolvedFixture.prepare(fixture));
		final owner = program.requireClass(program.requireClassIdentity("Main"));
		final entries:Array<CppManagedProgramFunction> = [];
		for (name in ["readFloat", "writeFloat"]) {
			final selected = owner.getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getDeclaration()) == name);
			if (selected.length != 1)
				throw "Float array fixture lost its exact method: " + name;
			entries.push({projection: selected[0], rootSymbol: "observe_" + name, symbolPrefix: "hxhx_function_float_array_" + name});
		}
		final header = new CppManagedProgramEmitter({
			functions: entries,
			output: [],
			classes: new backend.cpp.CppManagedClassStorage(program),
			defaultValue: type -> backend.cpp.CppManagedStaticDefault.render(program, type)
		}).render();
		final output = ".tmp/cpp-float-array-defaults";
		sys.FileSystem.createDirectory(output);
		sys.io.File.saveContent(output + "/FloatArray.hpp", header);
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
				"-I" + output,
				"-Ipackages/hxhx-core/runtime/cpp",
				"test/oracle/cpp_float_literal_seed/ArrayDefaults.cpp",
				"-o",
				binary
			]) != 0)
				throw "Float array observer failed to compile";
			final child = new sys.io.Process(binary, []);
			final stdout = child.stdout.readAll().toString();
			final stderr = child.stderr.readAll().toString();
			final code = child.exitCode();
			child.close();
			if (code != 0 || stdout != "" || stderr != "")
				throw "Float array observer failed: " + code + " " + stdout + stderr;
			Sys.println("CPP_FLOAT_ARRAY_DEFAULT:PASS " + optimization);
		}
	}
}
