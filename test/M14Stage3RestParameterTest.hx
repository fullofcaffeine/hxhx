import sys.io.File;

/**
	Prove that a written rest parameter such as `...parts:String` behaves like
	upstream Haxe inside the method body and at native OCaml runtime.

	Haxe gives the body a `haxe.Rest<T>` value, not a plain `Array<T>`. The
	standard library declares `Rest` as an abstract over an array that offers
	`toArray()`, `length`, indexed reads, and iteration. Callers still pass the
	variadic values one by one, and the compiler packs them into that value.
	The fixture covers fixed and rest-only signatures with zero, one, and many
	arguments, and uses each of those operations.
 */
class M14Stage3RestParameterTest {
	static function main():Void {
		final root = "test/fixtures/ocaml_rest_parameters";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_REST_PARAMETER_UPSTREAM:PASS");
		final prepared = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: root});
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram(prepared, false), ".tmp/ocaml_rest_parameters", true);
		M14Stage3RuntimeFixture.observe({command: artifact, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_REST_PARAMETER_NATIVE:PASS");
	}
}
