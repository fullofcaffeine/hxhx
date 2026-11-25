import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;

/**
	An array literal whose expected element type is a class or an interface accepts subclass
	and implementing elements, as upstream Haxe 4.3.7 does (haxe_ocaml-h9hun). Fixture:
	`test/fixtures/array_subclass_element`.

	Upstream unit `TestMain` collects generated spec classes in an array typed by their base
	class. hxhx's array-literal check had no ancestor rule, so `final xs:Array<Base> =
	[new Sub()]` failed with "array element Sub is not compatible with Base".

	- `Main` (a declared local, an interface element type, and a call argument) must type;
	  upstream prints `expected.stdout`.
	- `Wrong` (an unrelated class) must still fail, as upstream reports `Other should be Base`.
**/
class M14ArraySubclassElementTest {
	static final root = "test/fixtures/array_subclass_element";

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function compile(main:String):{code:Int, output:String} {
		final request = CompilationRequestContext.server(1);
		final code = Stage3Compiler.runRequest([
			"--hxhx-no-run",
			"--hxhx-no-emit",
			"--hxhx-out",
			".tmp/m14-array-subclass-element/" + main,
			"-cp",
			root,
			"-main",
			main
		], request);
		final output = new StringBuf();
		for (event in request.output.events())
			output.add(event.text);
		request.close(code == 0);
		return {code: code, output: output.toString()};
	}

	static function upstreamOutput():String {
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		require(code == 0, "upstream Haxe failed on the fixture:\n" + stdout + stderr);
		return stdout;
	}

	static function main():Void {
		require(upstreamOutput() == sys.io.File.getContent(root + "/expected.stdout"), "the fixture's expected.stdout no longer matches upstream Haxe");
		final accepted = compile("Main");
		require(accepted.code == 0, "subclass and implementing array elements were rejected:\n" + accepted.output);
		final rejected = compile("Wrong");
		require(rejected.code != 0 && rejected.output.indexOf("array element Other is not compatible with Base") >= 0,
			"an unrelated array element was accepted or reported differently:\n" + rejected.output);
		Sys.println("m14_array_subclass_element_test ok");
	}
}
