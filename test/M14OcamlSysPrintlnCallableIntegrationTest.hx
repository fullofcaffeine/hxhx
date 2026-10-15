import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Compare saved native output functions with upstream, including identity and Dynamic value conversion. */
class M14OcamlSysPrintlnCallableIntegrationTest {
	static function main():Void {
		// Dynamic belongs to Sys.println's public signature. The observer checks
		// the existing carrier conversion rather than adding an untyped adapter.
		final source = [
			"class Output {",
			"  public static var saved:Dynamic->Void = Sys.println;",
			"  public static function println(value:Int):Void Sys.println(value + 30);",
			"}",
			"class Main {",
			"  public var instance:Dynamic->Void;",
			"  public function new() { instance = Sys.println; }",
			"  static function main():Void {",
			"    var saved = Sys.println;",
			"    if (saved != Sys.println) throw 'output function identity changed';",
			"    saved('local');",
			"    saved(true); saved(false); saved(7); saved(null);",
			"    Output.saved('static');",
			"    new Main().instance('instance');",
			"    var nested = function():Void { var output = Sys.println; output('nested'); };",
			"    nested();",
			"    var user = Output.println; user(3);",
			"    saved('done');",
			"  }",
			"}"
		].join("\n");
		final expected = "local\ntrue\nfalse\n7\nnull\nstatic\ninstance\nnested\n33\ndone\n";
		final root = Path.join([Sys.getCwd(), ".tmp", "m14_ocaml_sys_println_callable"]);
		FileSystem.createDirectory(root);
		final path = Path.join([root, "Main.hx"]);
		File.saveContent(path, source);
		M14Stage3RuntimeFixture.observe({command: "haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		final typed = M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), Path.join([root, "ocaml"]), true);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("OCAML_SYS_PRINTLN_CALLABLE:PASS");
	}
}
