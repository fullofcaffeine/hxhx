import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;
import sys.FileSystem;
import sys.io.File;

/**
	An enum constructor with a function payload fails only where it is used (haxe_ocaml-fmiag).

	`haxe.macro.Type.TLazy(f:() -> Type)` has no native OCaml representation. A program that
	declares or imports `haxe.macro.Type` must still build: project-macro plugins compile it, and
	an emitting compile can reach it through an import. Building `TLazy`, or binding its payload in
	a pattern, fails with the emitter's existing message. `case TLazy(_)` stays allowed.

	Each case is compiled through the real Stage3 request pipeline (the OCaml backend and `dune`).
**/
class M14Stage3DeferredEnumPayloadTest {
	static inline final FAILURE = "OCaml enum payload representation is not implemented: haxe.macro.Type#static:TLazy";

	static final shell = [
		"import haxe.macro.Type;",
		"",
		"class Main {",
		"	static function kind(t:Type):String {",
		"		return switch t {",
		"			case TLazy(_): \"lazy\";",
		"			case TDynamic(_): \"dynamic\";",
		"			case TInst(c, params): \"inst \" + c.toString() + \" \" + params.length;",
		"			case _: \"other\";",
		"		};",
		"	}",
		"",
		"	static function main() {",
		"		final ref:Ref<ClassType> = {get: () -> throw \"not loaded\", toString: () -> \"Probe\"};",
		"		Sys.println(kind(TDynamic(null)));",
		"		Sys.println(kind(TInst(ref, [])));",
		"		Sys.println(kind(TFun([], TDynamic(null))));",
		"		USE",
		"	}",
		"}"
	].join("\n");

	static function main():Void {
		final root = haxe.io.Path.normalize(".tmp/m14_stage3_deferred_enum_payload_" + Std.string(Date.now().getTime()));
		FileSystem.createDirectory(root);

		final built = compile(root, "shell", "");
		require(built.code == 0, "a program that uses haxe.macro.Type without TLazy must build:\n" + built.output);
		final stdout = run(root + "/shell/out/out.exe");
		require(stdout == "dynamic\ninst Probe 0\nother\n", "the built program printed:\n" + stdout);

		final constructed = compile(root, "construct", "Sys.println(kind(TLazy(() -> TDynamic(null))));");
		require(constructed.code != 0 && constructed.output.indexOf(FAILURE) >= 0, "building TLazy must fail with the payload message:\n"
			+ constructed.output);

		final bound = compile(root, "bind", "switch TDynamic(null) { case TLazy(f): Sys.println(kind(f())); case _: }");
		require(bound.code != 0 && bound.output.indexOf(FAILURE) >= 0, "binding the TLazy payload must fail with the payload message:\n" + bound.output);

		// haxe_ocaml-q3mio: an emitting compile whose macro class imports `haxe.macro.Context` reaches
		// `haxe.macro.Type` through it. That compile must not stop on `TLazy` any more. Upstream prints
		// `hello`; until hxhx drops macro bodies from target compiles, it may stop on a later gap.
		final target = compileProgram(root + "/target", "test/fixtures/target_macro_context_import/src");
		require(target.output.indexOf(FAILURE) < 0, "an emitting compile that imports haxe.macro.Context must not fail on TLazy:\n" + target.output);
		if (target.code == 0)
			require(run(root + "/target/out/out.exe") == File.getContent("test/fixtures/target_macro_context_import/expected.stdout"),
				"the target_macro_context_import program must print upstream's output");

		deleteRecursive(root);
		Sys.println("M14_STAGE3_DEFERRED_ENUM_PAYLOAD:PASS");
	}

	static function compileProgram(out:String, source:String):{code:Int, output:String} {
		final context = new CompilationRequestContext(0, true, false);
		final code = Stage3Compiler.runRequest(["--hxhx-no-run", "--hxhx-out", out + "/out", "-cp", source, "-main", "Main"], context);
		final text = context.output.events().map(event -> event.text).join("");
		context.close(code == 0);
		return {code: code, output: text};
	}

	static function compile(root:String, name:String, use:String):{code:Int, output:String} {
		final source = root + "/" + name + "/src";
		FileSystem.createDirectory(source);
		File.saveContent(source + "/Main.hx", StringTools.replace(shell, "USE", use));
		final context = new CompilationRequestContext(0, true, false);
		final code = Stage3Compiler.runRequest([
			"--hxhx-no-run",
			"--hxhx-out",
			root + "/" + name + "/out",
			"-cp",
			source,
			"-main",
			"Main"
		], context);
		final text = context.output.events().map(event -> event.text).join("");
		context.close(code == 0);
		return {code: code, output: text};
	}

	static function run(command:String):String {
		final process = new sys.io.Process(command, []);
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
