/** Exercise typed enum construction through production C++ emission and native execution.
	Payload effects must occur once, in source order, before the result is published.
	This focused contract complements the full Dynamic equality matrix.
 */
class M14CppEnumConstructorIntegrationTest {
	static function main():Void {
		for (throws in [false, true])
			run(throws);
		Sys.println("CPP_ENUM_CONSTRUCTOR:PASS");
	}

	/** The throwing variant lets the native observer inspect state after unwinding. */
	static function run(throws:Bool):Void {
		final source = 'class Main {'
			+ ' static var order:Int = 0;'
			+ ' static var retained:Tree<Int>;'
			+ ' static var text:Tree<String>;'
			+ ' static function fail():Tree<Int> { throw "enum stop"; }'
			+ ' static var omitted:Tree<Int> = Tree.Maybe();'
			+ ' static function next(value:Int):Int { order = order * 10 + value; return value; }'
			+ ' static function main():Void {'
			+ ' retained = Tree.Pair(Tree.Leaf(next(1)), Tree.Leaf(next(2)));'
			+ ' text = Tree.Leaf("kept");'
			+ ' final supplied:Tree<Int> = Tree.Maybe(7);'
			+ ' final nested = function():Tree<Int> { return Tree.Leaf(3); }; nested();'
			+ ' if (order != 12) throw "enum argument order";'
			+ (throws ? ' retained = Tree.Pair(Tree.Leaf(next(3)), fail());' : '')
			+ ' } } enum Tree<T> { Leaf(value:T); Pair(first:Tree<T>, second:Tree<T>); Maybe(?value:T); }';
		final parsed = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final module = TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed]));
		final revision = CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity();
		final directory = ".tmp/cpp-enum-constructor" + (throws ? "-throw" : "");
		final result = backend.cpp.CppTargetCore.emit(new MacroExpandedProgram([module], false),
			new backend.BackendContext(directory, null, "Main", true, new haxe.ds.StringMap()));
		if (CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity() != revision)
			throw "enum construction changed its authored typed source";
		if (!result.builtExecutable)
			throw "enum construction did not build an executable";
		if (!throws) {
			final process = new sys.io.Process(result.entryPath, []);
			final output = process.stdout.readAll().toString();
			final errors = process.stderr.readAll().toString();
			final status = process.exitCode();
			process.close();
			if (status != 0 || output != "" || errors != "")
				throw "enum construction changed argument effects: " + status + " " + output + errors;
		}

		for (optimization in ["-O0", "-O2"]) {
			final executable = directory + "/stress" + optimization.substr(1);
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
				"-I" + directory + "/src",
				"-DEXPECT_THROW=" + (throws ? "1" : "0"),
				"test/fixtures/cpp_enum_constructor/Stress.cpp",
				"-o",
				executable
			]) != 0)
				throw "enum observer failed to compile: " + optimization;
			if (Sys.command(executable, []) != 0)
				throw "enum payload or collection contract failed: " + optimization;
			Sys.println("CPP_ENUM_CONSTRUCTOR:OBSERVER " + optimization + " throws=" + throws);
		}
	}
}
