import sys.FileSystem;
import sys.io.File;

/** Proves that native Stage3 preserves checked operations on Dynamic values. */
class M14HxhxStage3DynamicOperatorIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(haxe.io.Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function main():Void {
		final root = haxe.io.Path.normalize(".tmp/m14_hxhx_stage3_dynamic_operator");
		final sourceDir = haxe.io.Path.join([root, "src"]);
		final outputDir = haxe.io.Path.join([root, "out"]);
		final invalidOutputDir = haxe.io.Path.join([root, "out_invalid"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		FileSystem.createDirectory(sourceDir);

		final sourcePath = haxe.io.Path.join([sourceDir, "Main.hx"]);
		final source = [
			"class Main {",
			"  static function observed(value:Dynamic):Dynamic {",
			"    Sys.println(\"read=\" + value);",
			"    return value;",
			"  }",
			"  static function exactBool():Bool return true;",
			"  static function dynamicBool():Dynamic return exactBool();",
			"  static function apply(op:String, value:Dynamic):Dynamic {",
			"    var read:Dynamic = observed(value);",
			"    return switch (op) {",
			"      case \"not\": !read;",
			"      case \"neg\": -read;",
			"      case \"bits\": ~read;",
			"      case _: throw \"unsupported\";",
			"    };",
			"  }",
			"  static function binary(op:String, left:Dynamic, right:Dynamic):Dynamic {",
			"    return switch (op) {",
			"      case \"add\": left + right;",
			"      case \"sub\": left - right;",
			"      case \"mul\": left * right;",
			"      case \"div\": left / right;",
			"      case \"rem\": left % right;",
			"      case \"and\": left & right;",
			"      case \"or\": left | right;",
			"      case \"xor\": left ^ right;",
			"      case \"shl\": left << right;",
			"      case \"shr\": left >> right;",
			"      case \"ushr\": left >>> right;",
			"      case _: throw \"unsupported\";",
			"    };",
			"  }",
			"  static function less(left:Dynamic, right:Dynamic):Bool return left < right;",
			"  static function same(left:Dynamic, right:Dynamic):Bool return left == right;",
			"  static function both(left:Dynamic, right:Dynamic):Bool return left && observed(right);",
			"  static function either(left:Dynamic, right:Dynamic):Bool return left || observed(right);",
			"  static function inverted(value:Dynamic):Bool {",
			"    if (!value) return true;",
			"    return false;",
			"  }",
			"  static function main() {",
			"    Sys.println(apply(\"not\", true));",
			"    Sys.println(apply(\"not\", exactBool()));",
			"    Sys.println(apply(\"not\", dynamicBool()));",
			"    Sys.println(apply(\"neg\", 7));",
			"    Sys.println(apply(\"neg\", 1.5));",
			"    Sys.println(apply(\"bits\", 5));",
			"    Sys.println(binary(\"add\", 7, 5));",
			"    Sys.println(binary(\"sub\", 7, 5));",
			"    Sys.println(binary(\"mul\", 7, 5));",
			"    Sys.println(binary(\"div\", 5, 2));",
			"    Sys.println(binary(\"rem\", 7, 5));",
			"    Sys.println(binary(\"add\", \"a\", \"b\"));",
			"    Sys.println(binary(\"add\", \"a\", 2));",
			"    Sys.println(binary(\"add\", 2, \"a\"));",
			"    Sys.println(binary(\"add\", \"a\", true));",
			"    Sys.println(binary(\"and\", 6, 3));",
			"    Sys.println(binary(\"or\", 6, 3));",
			"    Sys.println(binary(\"xor\", 6, 3));",
			"    Sys.println(binary(\"shl\", 6, 2));",
			"    Sys.println(binary(\"shr\", 6, 1));",
			"    Sys.println(binary(\"ushr\", 8, 1));",
			"    Sys.println(less(2, 3));",
			"    Sys.println(same(3, 3));",
			"    Sys.println(both(false, true));",
			"    Sys.println(both(true, false));",
			"    Sys.println(either(true, false));",
			"    Sys.println(either(false, true));",
			"    Sys.println(inverted(true));",
			"    Sys.println(inverted(false));",
			"  }",
			"}",
		].join("\n");
		File.saveContent(sourcePath, source);
		final expected = "read=true\nfalse\nread=true\nfalse\nread=true\nfalse\nread=7\n-7\nread=1.5\n-1.5\nread=5\n-6\n12\n2\n35\n2.5\n2\nab\na2\n2a\natrue\n2\n7\n5\n24\n3\n4\ntrue\ntrue\nfalse\nread=false\nfalse\ntrue\nread=true\ntrue\nfalse\ntrue\n";

		final versionProcess = new sys.io.Process("haxe", ["--version"]);
		final haxeVersion = versionProcess.stdout.readAll().toString();
		final versionError = versionProcess.stderr.readAll().toString();
		final versionCode = versionProcess.exitCode();
		versionProcess.close();
		assertTrue(versionCode == 0 && StringTools.startsWith(StringTools.trim(haxeVersion), "4.3.7"),
			"The Dynamic operator oracle requires Haxe 4.3.7: " + versionError);
		final oracleProcess = new sys.io.Process("haxe", ["-cp", sourceDir, "-main", "Main", "--interp"]);
		final oracleStdout = oracleProcess.stdout.readAll().toString();
		final oracleStderr = oracleProcess.stderr.readAll().toString();
		final oracleCode = oracleProcess.exitCode();
		oracleProcess.close();
		assertTrue(oracleCode == 0, "Haxe 4.3.7 Dynamic operator oracle failed: " + oracleStderr);
		assertTrue(oracleStdout == expected, "Unexpected Haxe 4.3.7 Dynamic operator output:\n" + oracleStdout);

		final exprToolsSource = File.getContent("vendor/haxe/std/haxe/macro/ExprTools.hx");
		for (shape in [
			"var e1:Dynamic = getValue(e1);",
			"case OpNot: !e1;",
			"case OpNeg: -e1;",
			"case OpNegBits: ~e1;",
			"var e2:Dynamic = getValue(e2);",
			"case OpBoolAnd: e1 && e2;",
			"case OpBoolOr: e1 || e2;"
		])
			assertTrue(exprToolsSource.indexOf(shape) >= 0, "The focused fixture drifted from the Haxe 4.3.7 ExprTools.getValue shape: " + shape);

		final parsed = ParserStage.parse(source, sourcePath);
		final typed = TyperStage.typeModule(parsed);
		final expanded = MacroStage.expandProgram([typed], []);
		final executable = EmitterStage.emitToDir(expanded, outputDir, true);
		final generated = File.getContent(haxe.io.Path.join([outputDir, "Main.ml"]));

		assertTrue(generated.indexOf("(value : Obj.t)") >= 0, "Dynamic parameter did not use the Obj.t carrier.");
		assertTrue(generated.indexOf("HxRuntime.box_bool (true)") >= 0, "Bool did not receive the distinct Dynamic box at the call boundary.");
		assertTrue(generated.indexOf("HxDynamic.logicalNot") >= 0, "Dynamic logical-not did not use the checked runtime operation.");
		assertTrue(generated.indexOf("HxDynamic.negate") >= 0, "Dynamic negation did not use the checked runtime operation.");
		assertTrue(generated.indexOf("HxDynamic.bitwiseNot") >= 0, "Dynamic bitwise complement did not use the checked runtime operation.");
		assertTrue(generated.indexOf("HxDynamic.add") >= 0, "Dynamic addition did not use the checked runtime operation.");
		assertTrue(generated.indexOf("HxDynamic.lessThan") >= 0, "Dynamic comparison did not use the checked runtime operation.");
		assertTrue(generated.indexOf("HxRuntime.dynamic_equals") >= 0, "Dynamic equality did not use the checked runtime operation.");
		assertTrue(generated.indexOf("HxDynamic.booleanValue") >= 0, "Dynamic short-circuit logic did not use checked Boolean values.");
		assertTrue(generated.indexOf("HxDynamic.logicalNot (Obj.repr (read))") >= 0, "The ExprTools-shaped Dynamic local did not use checked logical-not.");
		assertTrue(generated.indexOf("HxDynamic.negate (Obj.repr (read))") >= 0, "The ExprTools-shaped Dynamic local did not use checked negation.");
		assertTrue(generated.indexOf("HxDynamic.bitwiseNot (Obj.repr (read))") >= 0,
			"The ExprTools-shaped Dynamic local did not use checked bitwise complement.");
		assertTrue(generated.indexOf("not (read)") < 0 && generated.indexOf("-(read)") < 0 && generated.indexOf("HxInt.lognot (read)") < 0,
			"The ExprTools-shaped Dynamic local still reached a raw OCaml operator.");

		final result = new sys.io.Process(executable, []);
		final stdout = result.stdout.readAll().toString();
		final stderr = result.stderr.readAll().toString();
		final code = result.exitCode();
		result.close();
		assertTrue(code == 0, "Dynamic unary executable failed: " + stderr);
		assertTrue(stdout == expected, "Native Dynamic operators differed from Haxe 4.3.7:\n" + stdout);

		// Keep rejection evidence independent from Stage3 try/catch support. The
		// failing program prints its operand before the checked runtime call, which
		// also proves that the operand was evaluated exactly once.
		final invalidSourcePath = haxe.io.Path.join([sourceDir, "InvalidMain.hx"]);
		final invalidSource = [
			"class InvalidMain {",
			"  static function observed(value:Dynamic):Dynamic {",
			"    Sys.println(\"invalid-read=\" + value);",
			"    return value;",
			"  }",
			"  static function main() {",
			"    Sys.println(-observed(\"text\"));",
			"  }",
			"}",
		].join("\n");
		File.saveContent(invalidSourcePath, invalidSource);
		final invalidParsed = ParserStage.parse(invalidSource, invalidSourcePath);
		final invalidTyped = TyperStage.typeModule(invalidParsed);
		final invalidExpanded = MacroStage.expandProgram([invalidTyped], []);
		final invalidExecutable = EmitterStage.emitToDir(invalidExpanded, invalidOutputDir, true);
		final invalidResult = new sys.io.Process(invalidExecutable, []);
		final invalidStdout = invalidResult.stdout.readAll().toString();
		final invalidStderr = invalidResult.stderr.readAll().toString();
		final invalidCode = invalidResult.exitCode();
		invalidResult.close();
		assertTrue(invalidCode != 0, "Unsupported Dynamic negation unexpectedly succeeded.");
		assertTrue(invalidStdout == "invalid-read=text\n", "Dynamic rejection evaluated its operand incorrectly:\n" + invalidStdout);
		assertTrue(invalidStderr.indexOf("Invalid Dynamic negation operand; expected Int or Float") >= 0,
			"Dynamic rejection did not report the stable checked error:\n" + invalidStderr);
	}
}
