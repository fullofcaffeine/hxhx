import haxe.ds.StringMap;
import sys.FileSystem;
import sys.io.File;
import TypedExpr.TypedExprTag;

/**
	Proves that mixed Int and Float multiplication keeps its Float result.

	Stage3 must use the selected call result and both operand types. It must not
	choose integer multiplication only because the left operand is an Int.
**/
class M14HxhxStage3MixedNumericMultiplicationIntegrationTest {
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

	static function run(command:String, arguments:Array<String>):{exitCode:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final exitCode = process.exitCode();
		process.close();
		return {exitCode: exitCode, stdout: stdout, stderr: stderr};
	}

	static function findFunction(module:TypedModule, className:String, functionName:String):TypedFunction {
		for (typedClass in module.getTypedClasses())
			if (HxClassDecl.getName(typedClass.getSourceDeclaration()) == className)
				for (typedFunction in typedClass.getFunctions())
					if (HxFunctionDecl.getName(typedFunction.getSourceDeclaration()) == functionName)
						return typedFunction;
		throw "missing " + className + "." + functionName;
	}

	static function collectExpressions(expression:TypedExpr, result:Array<TypedExpr>):Void {
		result.push(expression);
		for (child in expression.getExpressions())
			collectExpressions(child, result);
	}

	static function collectStatementExpressions(statement:TypedStmt, result:Array<TypedExpr>):Void {
		for (expression in statement.getExpressions())
			collectExpressions(expression, result);
		for (child in statement.getStatements())
			collectStatementExpressions(child, result);
	}

	static function functionExpressions(fn:TypedFunction):Array<TypedExpr> {
		final result = new Array<TypedExpr>();
		for (statement in fn.getBody().getStatements())
			collectStatementExpressions(statement, result);
		return result;
	}

	static function requireBinary(fn:TypedFunction, op:String, leftType:String, rightType:String, resultType:String):TypedExpr {
		for (expression in functionExpressions(fn)) {
			if (expression.getTag() != TypedExprTag.Binary || expression.getTexts().length != 1 || expression.getTexts()[0] != op)
				continue;
			final children = expression.getExpressions();
			if (children.length != 2)
				continue;
			if (children[0].getType().getSemanticKey() == leftType
				&& children[1].getType().getSemanticKey() == rightType
				&& expression.getType().getSemanticKey() == resultType)
				return expression;
		}
		throw "missing typed binary " + op + " with " + leftType + ", " + rightType + " -> " + resultType;
	}

	static function requireCall(fn:TypedFunction, name:String, resultType:String, argumentType:String):Void {
		for (expression in functionExpressions(fn)) {
			if (expression.getTag() != TypedExprTag.Call)
				continue;
			final children = expression.getExpressions();
			if (children.length != 2 || children[0].getTexts().length != 1 || children[0].getTexts()[0] != name)
				continue;
			assertTrue(expression.getType().getSemanticKey() == resultType, name + " lost its result type");
			assertTrue(children[1].getType().getSemanticKey() == argumentType, name + " lost its argument type");
			return;
		}
		throw "missing call to " + name;
	}

	static function countOccurrences(text:String, needle:String):Int {
		var count = 0;
		var offset = 0;
		while (true) {
			final found = text.indexOf(needle, offset);
			if (found < 0)
				return count;
			count++;
			offset = found + needle.length;
		}
	}

	static function main():Void {
		final root = haxe.io.Path.normalize(".tmp/m14_hxhx_stage3_mixed_numeric_multiplication");
		final sourceDir = haxe.io.Path.join([root, "src"]);
		final outDir = haxe.io.Path.join([root, "out"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		FileSystem.createDirectory(sourceDir);

		final sourcePath = haxe.io.Path.join([sourceDir, "MixedNumericMultiplication.hx"]);
		final source = [
			"class MixedNumericMultiplication {",
			"  static function observed(label:String, value:Float):Float {",
			"    Sys.println('read=' + label);",
			"    return value;",
			"  }",
			"  static function intLeft():Float return 4 * observed('left', 1.25);",
			"  static function floatLeft():Float return observed('right', 1.25) * 4;",
			"  static function rounded(timeout:Int, start:Float, now:Float):Int",
			"    return timeout - Math.round(1000 * (now - start));",
			"  static function roundedCall(timeout:Int):Int",
			"    return timeout - Math.round(1000 * observed('now', 1.25));",
			"  static function roundScaled(scale:Int, value:Float):Int return Math.round(scale * value);",
			"  static function pureInt():Int return 6 * 7;",
			"  static function main():Void {",
			"    Sys.println(Math.round(intLeft() * 100));",
			"    Sys.println(Math.round(floatLeft() * 100));",
			"    Sys.println(rounded(5000, 8.875, 10.125));",
			"    Sys.println(roundedCall(5000));",
			"    Sys.println(roundScaled(3, -0.5));",
			"    Sys.println(pureInt());",
			"  }",
			"}",
		].join("\n");
		File.saveContent(sourcePath, source);
		File.saveContent(haxe.io.Path.join([sourceDir, "MixedNumericMultiplicationProbe.hx"]), [
			"import haxe.macro.Context;",
			"import haxe.macro.Type;",
			"import haxe.macro.TypeTools;",
			"import haxe.macro.TypedExprTools;",
			"class MixedNumericMultiplicationProbe {",
			"  public static macro function verify():Void {",
			"    final owner = switch Context.getType('MixedNumericMultiplication') {",
			"      case TInst(reference, _): reference.get();",
			"      case other: Context.fatalError('expected class, got ' + TypeTools.toString(other), Context.currentPos());",
			"    };",
			"    final expected = new Map<String, Array<String>>();",
			"    expected.set('intLeft', ['Int', 'Float', 'Float']);",
			"    expected.set('floatLeft', ['Float', 'Int', 'Float']);",
			"    expected.set('rounded', ['Int', 'Float', 'Float']);",
			"    expected.set('roundedCall', ['Int', 'Float', 'Float']);",
			"    expected.set('roundScaled', ['Int', 'Float', 'Float']);",
			"    expected.set('pureInt', ['Int', 'Int', 'Int']);",
			"    for (field in owner.statics.get()) {",
			"      final wanted = expected.get(field.name);",
			"      if (wanted == null) continue;",
			"      final expression = field.expr();",
			"      if (expression == null) Context.fatalError('missing expression for ' + field.name, field.pos);",
			"      var found = false;",
			"      function walk(value:haxe.macro.Type.TypedExpr):Void {",
			"        switch value.expr {",
			"          case TBinop(OpMult, left, right):",
			"            final types = [TypeTools.toString(left.t), TypeTools.toString(right.t), TypeTools.toString(value.t)];",
			"            if (types.join(',') == wanted.join(',')) found = true;",
			"          case _:",
			"        }",
			"        TypedExprTools.iter(value, walk);",
			"      }",
			"      walk(expression);",
			"      if (!found) Context.fatalError('missing typed multiplication for ' + field.name, field.pos);",
			"    }",
			"  }",
			"}",
		].join("\n"));

		final upstreamVersion = run("haxe", ["--version"]);
		assertTrue(upstreamVersion.exitCode == 0 && StringTools.trim(upstreamVersion.stdout) == "4.3.7",
			"the mixed numeric oracle must be upstream Haxe 4.3.7: " + upstreamVersion.stdout + upstreamVersion.stderr);
		final upstream = run("haxe", [
			"-cp",
			sourceDir,
			"-main",
			"MixedNumericMultiplication",
			"--interp",
			"--macro",
			"MixedNumericMultiplicationProbe.verify()"
		]);
		final expected = "read=left\n500\nread=right\n500\n3750\nread=now\n3750\n-1\n42\n";
		assertTrue(upstream.exitCode == 0, "Haxe 4.3.7 rejected the mixed numeric contract: " + upstream.stderr);
		assertTrue(upstream.stdout == expected, "unexpected Haxe 4.3.7 mixed numeric output: " + upstream.stdout);

		final parsed = ParserStage.parse(source, sourcePath);
		final resolved = new ResolvedModule("MixedNumericMultiplication", sourcePath, parsed);
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader([sourceDir], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index, loader);
		requireBinary(findFunction(typed, "MixedNumericMultiplication", "intLeft"), "*", "primitive:Int", "primitive:Float", "primitive:Float");
		requireBinary(findFunction(typed, "MixedNumericMultiplication", "floatLeft"), "*", "primitive:Float", "primitive:Int", "primitive:Float");
		final rounded = findFunction(typed, "MixedNumericMultiplication", "rounded");
		requireBinary(rounded, "-", "primitive:Float", "primitive:Float", "primitive:Float");
		requireBinary(rounded, "*", "primitive:Int", "primitive:Float", "primitive:Float");
		requireBinary(rounded, "-", "primitive:Int", "primitive:Int", "primitive:Int");
		requireCall(rounded, "round", "primitive:Int", "primitive:Float");
		final roundedCall = findFunction(typed, "MixedNumericMultiplication", "roundedCall");
		requireBinary(roundedCall, "*", "primitive:Int", "primitive:Float", "primitive:Float");
		requireCall(roundedCall, "round", "primitive:Int", "primitive:Float");
		requireBinary(findFunction(typed, "MixedNumericMultiplication", "pureInt"), "*", "primitive:Int", "primitive:Int", "primitive:Int");

		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), outDir, true);
		final generated = File.getContent(haxe.io.Path.join([outDir, "MixedNumericMultiplication.ml"]));
		assertTrue(countOccurrences(generated, "*.") >= 5, "mixed multiplication did not use Float operators: " + generated);
		assertTrue(generated.indexOf("HxInt.mul (1000)") < 0, "the elapsed-time scale still used Int multiplication: " + generated);
		assertTrue(generated.indexOf("HxInt.mul (6) (7)") >= 0, "pure Int multiplication lost HxInt semantics: " + generated);

		final nativeResult = run(executable, []);
		assertTrue(nativeResult.exitCode == 0, "native mixed numeric executable failed: " + nativeResult.stderr);
		assertTrue(nativeResult.stdout == expected, "native mixed numeric output differs from Haxe 4.3.7: " + nativeResult.stdout);
		deleteRecursive(root);
	}
}
