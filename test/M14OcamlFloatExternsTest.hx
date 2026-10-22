import sys.io.File;

/** Preserve Float values across real native exports without changing numerical algorithms. */
class M14OcamlFloatExternsTest {
	/** An Int-returning export must not satisfy a declared Float result through erased printing. */
	static function rejectWrongResult(output:String):Void {
		final source = '@:native("HxString") extern class Host { public static function length(value:String):Float; }'
			+ 'class Main { static function main():Void { Sys.println(Host.length("abc")); } }';
		final module = M14Stage3RuntimeFixture.typeMain({source: source, path: "Main.hx", root: "."});
		final mismatch = ".tmp/ocaml_float_extern_wrong_result";
		EmitterStage.emitToDir(new MacroExpandedProgram([module], false), mismatch, true, false);
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, [
			"30",
			"ocamlc",
			"-I",
			output + "/runtime",
			"-I",
			output,
			"-c",
			mismatch + "/Main.ml"
		]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		if (status == 0 || stdout != "" || stderr.indexOf("string -> int") < 0 || stderr.indexOf("string -> float") < 0)
			throw "native checker did not reject the false Float result: " + stderr;
		Sys.println("OCAML_FLOAT_EXTERN_ABI_REJECTION:PASS");
	}

	static function main():Void {
		final root = "test/fixtures/ocaml_float_externs";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("OCAML_FLOAT_EXTERN_UPSTREAM:PASS");
		final source = HxConditionalCompilation.filterSource(File.getContent(path),
			hxhx.Stage3SetupSupport.buildDefinesMap(["native_host"], "ocaml", "ocaml-stage3"));
		final module = M14Stage3RuntimeFixture.prepareMain({source: source, path: path, root: root});
		final output = ".tmp/ocaml_float_externs";
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([module], false), output, true, true);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("OCAML_FLOAT_EXTERN_RUNTIME:PASS");
		rejectWrongResult(output);
	}
}
