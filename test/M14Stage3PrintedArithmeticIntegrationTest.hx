import sys.FileSystem;
import sys.io.File;

/** Printing consumes the computed value without redefining addition or reversing operand effects. */
class M14Stage3PrintedArithmeticIntegrationTest {
	static function main():Void {
		final source = [
			"class Main {",
			"  static function identity<T>(value:T):T return value;",
			"  static function number(value:Int):Int return value;",
			"  static function apply(callback:Int->Int):Int return callback(5) + callback(6);",
			"  static function alias(callback:Int->Int):Int { var saved = callback; return saved(5) + saved(6); }",
			"  static function observe(label:String, value:Int):Int { Sys.println(label); return value; }",
			"  static function fail():Int { Sys.println('throw'); throw 'stopped'; }",
			"  static function main():Void {",
			"    var a = 42; var b = 7;",
			"    Sys.println(42 + 7);",
			"    Sys.println(a + b);",
			"    Sys.println(Std.string(a + b + number(3) + number(7)));",
			"    Sys.println((number(3) + number(7)) + (number(2) + number(4)));",
			"    Sys.println(identity(3) + identity(7));",
			"    Sys.println(apply(number)); Sys.println(alias(number));",
			"    Sys.println('sum=' + (number(3) + number(7)));",
			"    Sys.println('digits=' + 3 + 7);",
			"    Sys.println(observe('left', 3) + observe('right', 7));",
			"    Sys.println(apply(value -> observe(Std.string(value), value)));",
			"    Sys.println(observe('sub-left', 9) - observe('sub-right', 4));",
			"    Sys.println(observe('mul-left', 9) * observe('mul-right', 4));",
			"    Sys.println(observe('rem-left', 9) % observe('rem-right', 4));",
			"    try { Sys.println(fail() + observe('unreachable', 2)); } catch (error:String) { Sys.println(error); }",
			"    Sys.println('done');",
			"  }",
			"}"
		].join("\n");
		final expected = "49\n49\n59\n16\n10\n11\n11\nsum=10\ndigits=37\nleft\nright\n10\n5\n6\n11\n"
			+ "sub-left\nsub-right\n5\nmul-left\nmul-right\n36\nrem-left\nrem-right\n1\nthrow\nstopped\ndone\n";
		check("callback", source, expected);
		check("instance", [
			"class Main {",
			"  public function new() {}",
			"  public function member(label:String, value:Int):Int { Sys.println(label); return value; }",
			"  static function main():Void {",
			"    var owner = new Main();",
			"    Sys.println(owner.member('left', 3) + owner.member('right', 7));",
			"  }",
			"}"
		].join("\n"), "left\nright\n10\n");
		Sys.println("M14_STAGE3_PRINTED_ARITHMETIC:PASS");
	}

	/** Use the same authored source and independent expected transcript for both compilers. */
	static function check(name:String, source:String, expected:String):Void {
		final root = ".tmp/m14_stage3_printed_arithmetic_" + name;
		FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		File.saveContent(path, source);
		M14Stage3RuntimeFixture.observe({command: "haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		final typed = M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), root + "/ocaml", true);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
	}
}
