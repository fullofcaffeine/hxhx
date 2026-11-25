import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;
import sys.FileSystem;
import sys.io.File;

/**
	A target compile does not type or emit macro function bodies (haxe_ocaml-q3mio, PR A).

	Upstream Haxe 4.3.7 types a macro function's body only in its macro context; the program sees
	the function without a body (`typeloadFields.ml`, lines 1298-1345). hxhx's macro context is the
	project-macro plugin build. Before this change, an emitting compile of a class with an
	unguarded macro function typed the body, and `$v{[1, 2]}` failed: "the support module
	hxhxmacrohost.MacroReificationValues is not on the classpath". A body that names
	`haxe.macro.Context` still brings that module in: the resolver's qualified-name scan reads the
	whole source (see the plan's known gaps).

	`test/fixtures/target_macro_body` must build as an ordinary program and print what haxe 4.3.7
	prints (`expected.stdout`). hxhx's own `CompilerBundledSourcesMacro.files` keeps its body for
	the bootstrap (`MacroCompilationContext.isBundledSourcesMacro`).
**/
class M14TargetMacroBodySkipTest {
	static inline final FIXTURE = "test/fixtures/target_macro_body";
	static final FixtureRoot = FileSystem.absolutePath(FIXTURE + "/src");

	static function main():Void {
		final expected = File.getContent(FIXTURE + "/expected.stdout");
		require(run("node_modules/.bin/haxe", ["-cp", FIXTURE + "/src", "--run", "Main"]) == expected, "upstream output differs from expected.stdout");

		final root = haxe.io.Path.normalize(".tmp/m14_target_macro_body_skip_" + Std.string(Date.now().getTime()));
		FileSystem.createDirectory(root);
		final context = new CompilationRequestContext(0, true, false);
		final code = Stage3Compiler.runRequest([
			"--hxhx-no-run",
			"--hxhx-out",
			root + "/out",
			"-cp",
			FIXTURE + "/src",
			"-main",
			"Main"
		], context);
		final output = context.output.events().map(event -> event.text).join("");
		context.close(code == 0);
		require(code == 0, "a program whose macro class has unguarded macro bodies must build:\n" + output);
		final actual = run(root + "/out/out.exe", []);
		require(actual == expected, "hxhx output differs from haxe 4.3.7:\n" + actual);

		// hxhx's own bundled-sources macro keeps its body when hxhx compiles itself; a project class
		// with the same name elsewhere does not.
		final bundled = FileSystem.absolutePath("packages/hxhx-core/src/CompilerBundledSourcesMacro.hx");
		require(MacroCompilationContext.isBundledSourcesMacro("CompilerBundledSourcesMacro.files", bundled), "hxhx's bundled-sources macro must keep its body");
		require(!MacroCompilationContext.isBundledSourcesMacro("CompilerBundledSourcesMacro.files", FixtureRoot + "/CompilerBundledSourcesMacro.hx"),
			"a project class with the same name must not keep its macro body");
		require(!MacroCompilationContext.standardMacroModulesOnly().typesMacroBodies("Macros", FixtureRoot + "/Macros.hx"),
			"an ordinary compile must not type macro bodies");

		deleteRecursive(root);
		Sys.println("M14_TARGET_MACRO_BODY_SKIP:PASS");
	}

	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		require(code == 0, command + " exited " + code + ": " + errors);
		return output;
	}

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(path + "/" + entry);
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}
}
