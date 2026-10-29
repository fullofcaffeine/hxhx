import sys.io.File;

/**
	Call a runtime-provided OCaml method whose Haxe name is an OCaml keyword.

	`EReg` has no generated module: its OCaml body is the shared runtime file
	`EReg.ml`, which exports Haxe `match` as `hx_match`. A stage3 call must use
	that exported name, not the `match_` spelling that stage3 gives to the
	modules it writes itself.

	The native build is the check: OCaml rejects any call to a name that the
	runtime module does not export. The program is not run, because stage3 does
	not yet construct runtime-provided externs such as `new EReg(...)`
	(Bead haxe_ocaml-r4ylw).
 */
class M14OcamlRuntimeKeywordMethodTest {
	static function main():Void {
		final source = [
			'class Main {',
			'  static var rx = ~/[A-Za-z0-9_."-]+/;',
			'  static function main():Void {',
			'    Sys.println(Std.string(rx.match("abc")));',
			'    Sys.println(rx.matched(0));',
			'  }',
			'}',
			''
		].join("\n");
		final module = M14Stage3RuntimeFixture.prepareMain({source: source, path: "Main.hx", root: "."});
		final output = ".tmp/ocaml_runtime_keyword_method";
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([module], false), output, true);
		if (executable == null || !sys.FileSystem.exists(executable))
			throw "native build did not produce an executable";
		final generated = File.getContent(output + "/Main.ml");
		if (generated.indexOf("EReg.hx_match") < 0 || generated.indexOf("EReg.match_") >= 0 || generated.indexOf("EReg.matched") < 0)
			throw "runtime EReg calls do not use the runtime export names: " + generated;
		Sys.println("OCAML_RUNTIME_KEYWORD_METHOD:PASS");
	}
}
