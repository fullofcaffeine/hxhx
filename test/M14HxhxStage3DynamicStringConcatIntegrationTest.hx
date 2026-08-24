import haxe.ds.StringMap;
import sys.FileSystem;
import sys.io.File;
import TypedExpr.TypedExprTag;

/**
	Proves that String concatenation keeps its typed result across Dynamic values.

	Haxe types every nested addition in a String-led chain as String. Native
	Stage3 must preserve that result after a Dynamic operand uses the checked
	addition runtime. A later literal must receive a String, not the underlying
	`Obj.t` Dynamic carrier.
**/
class M14HxhxStage3DynamicStringConcatIntegrationTest {
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

	static function collectStringAdditions(expression:TypedExpr, result:Array<TypedExpr>):Void {
		if (expression.getTag() == TypedExprTag.Binary && expression.getTexts().length == 1 && expression.getTexts()[0] == "+")
			result.push(expression);
		for (child in expression.getExpressions())
			collectStringAdditions(child, result);
	}

	static function collectStatementStringAdditions(statement:TypedStmt, result:Array<TypedExpr>):Void {
		for (expression in statement.getExpressions())
			collectStringAdditions(expression, result);
		for (child in statement.getStatements())
			collectStatementStringAdditions(child, result);
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
		final root = haxe.io.Path.normalize(".tmp/m14_hxhx_stage3_dynamic_string_concat");
		final sourceDir = haxe.io.Path.join([root, "src"]);
		final outDir = haxe.io.Path.join([root, "out"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		FileSystem.createDirectory(sourceDir);

		final sourcePath = haxe.io.Path.join([sourceDir, "DynamicStringConcat.hx"]);
		final source = [
			"class DynamicStringConcat {",
			"  static function observed(value:Dynamic):Dynamic return value;",
			"  static function chain(left:Dynamic, right:Dynamic):String",
			"    return \"left=\" + observed(left) + \",right=\" + observed(right) + \"!\";",
			"  static function numeric(left:Dynamic, right:Dynamic):Dynamic return left + right;",
			"  static function main():Void {",
			"    Sys.println(chain(\"text\", 7));",
			"    Sys.println(chain(1.5, true));",
			"    Sys.println(chain(null, \"tail\"));",
			"    Sys.println(numeric(2, 3));",
			"  }",
			"}",
		].join("\n");
		File.saveContent(sourcePath, source);
		File.saveContent(haxe.io.Path.join([sourceDir, "DynamicStringConcatProbe.hx"]), [
			"import haxe.macro.Context;",
			"import haxe.macro.Type;",
			"import haxe.macro.TypeTools;",
			"import haxe.macro.TypedExprTools;",
			"class DynamicStringConcatProbe {",
			"  public static macro function verify():Void {",
			"    final owner = switch Context.getType('DynamicStringConcat') {",
			"      case TInst(reference, _): reference.get();",
			"      case other: Context.fatalError('expected class, got ' + TypeTools.toString(other), Context.currentPos());",
			"    };",
			"    final field = owner.statics.get().filter(candidate -> candidate.name == 'chain')[0];",
			"    final expression = field.expr();",
			"    if (expression == null) Context.fatalError('missing chain expression', field.pos);",
			"    var additions = 0;",
			"    function walk(value:haxe.macro.Type.TypedExpr):Void {",
			"      switch value.expr {",
			"        case TBinop(OpAdd, _, _):",
			"          additions++;",
			"          if (TypeTools.toString(value.t) != 'String')",
			"            Context.fatalError('nested addition must be String, got ' + TypeTools.toString(value.t), value.pos);",
			"        case _:",
			"      }",
			"      TypedExprTools.iter(value, walk);",
			"    }",
			"    walk(expression);",
			"    if (additions != 4) Context.fatalError('expected four nested String additions, got ' + additions, field.pos);",
			"  }",
			"}",
		].join("\n"));

		final upstreamVersion = run("haxe", ["--version"]);
		assertTrue(upstreamVersion.exitCode == 0 && StringTools.trim(upstreamVersion.stdout) == "4.3.7",
			"the Dynamic String oracle must be upstream Haxe 4.3.7: " + upstreamVersion.stdout + upstreamVersion.stderr);
		final upstream = run("haxe", [
			"-cp",
			sourceDir,
			"-main",
			"DynamicStringConcat",
			"--interp",
			"--macro",
			"DynamicStringConcatProbe.verify()"
		]);
		final expected = "left=text,right=7!\nleft=1.5,right=true!\nleft=null,right=tail!\n5\n";
		assertTrue(upstream.exitCode == 0, "Haxe 4.3.7 rejected the Dynamic String contract: " + upstream.stderr);
		assertTrue(upstream.stdout == expected, "unexpected Haxe 4.3.7 Dynamic String output: " + upstream.stdout);

		final parsed = ParserStage.parse(source, sourcePath);
		final resolved = new ResolvedModule("DynamicStringConcat", sourcePath, parsed);
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader([sourceDir], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index, loader);
		final additions = new Array<TypedExpr>();
		for (statement in findFunction(typed, "DynamicStringConcat", "chain").getBody().getStatements())
			collectStatementStringAdditions(statement, additions);
		assertTrue(additions.length == 4, "hxhx did not retain the four nested additions");
		for (addition in additions)
			assertTrue(addition.getType().getSemanticKey() == "primitive:String", "hxhx lost a nested String addition result");

		final expanded = MacroStage.expandProgram([typed], []);
		EmitterStage.emitToDir(expanded, outDir, true, false);
		final generated = File.getContent(haxe.io.Path.join([outDir, "DynamicStringConcat.ml"]));
		final executable = EmitterStage.emitToDir(expanded, outDir, true);
		assertTrue(countOccurrences(generated, "observed (left)") == 1, "the left Dynamic expression was emitted more than once: " + generated);
		assertTrue(countOccurrences(generated, "observed (right)") == 1, "the right Dynamic expression was emitted more than once: " + generated);
		assertTrue(countOccurrences(generated, "HxDynamic.add") == 3,
			"the two mixed String additions and one Dynamic numeric addition did not retain checked runtime dispatch: " + generated);
		assertTrue(countOccurrences(generated, "HxDynamic.toStdString (HxDynamic.add") == 2,
			"the mixed String additions did not restore their two concrete String results: " + generated);

		final nativeResult = run(executable, []);
		assertTrue(nativeResult.exitCode == 0, "native Dynamic String executable failed: " + nativeResult.stderr);
		assertTrue(nativeResult.stdout == expected, "native Dynamic String output differs from Haxe 4.3.7: " + nativeResult.stdout);
		deleteRecursive(root);
	}
}
