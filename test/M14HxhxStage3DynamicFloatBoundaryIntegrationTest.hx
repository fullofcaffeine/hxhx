import haxe.ds.StringMap;
import sys.FileSystem;
import sys.io.File;
import TypedExpr.TypedExprTag;

/**
	Proves that a Dynamic argument crosses a declared Float boundary safely.

	Haxe keeps the source argument typed as Dynamic, even inside a
	`Type.typeof` numeric case. The selected function declaration supplies the
	Float contract. Native OCaml must therefore validate and convert the runtime
	carrier at the call instead of pretending the source value was statically
	Float.
**/
class M14HxhxStage3DynamicFloatBoundaryIntegrationTest {
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

	static function findCall(expression:TypedExpr, name:String):Null<TypedExpr> {
		if (expression.getTag() == TypedExprTag.Call) {
			final children = expression.getExpressions();
			if (children.length > 0 && children[0].getTexts().length == 1 && children[0].getTexts()[0] == name)
				return expression;
		}
		for (child in expression.getExpressions()) {
			final found = findCall(child, name);
			if (found != null)
				return found;
		}
		return null;
	}

	static function findCallInStatement(statement:TypedStmt, name:String):Null<TypedExpr> {
		for (expression in statement.getExpressions()) {
			final found = findCall(expression, name);
			if (found != null)
				return found;
		}
		for (child in statement.getStatements()) {
			final found = findCallInStatement(child, name);
			if (found != null)
				return found;
		}
		return null;
	}

	static function findFunctionCall(functionDeclaration:TypedFunction, name:String):TypedExpr {
		for (statement in functionDeclaration.getBody().getStatements()) {
			final found = findCallInStatement(statement, name);
			if (found != null)
				return found;
		}
		throw "missing call to " + name;
	}

	static function assertDynamicFloatCall(call:TypedExpr, label:String):Void {
		final children = call.getExpressions();
		assertTrue(children.length == 2, label + " call lost its argument");
		assertTrue(children[1].getType().isDynamic(), label + " argument did not retain its upstream Dynamic type");
		assertTrue(call.getType().getSemanticKey() == "primitive:Float", label + " call did not retain its Float result");
		final declaration = call.getDeclaration();
		assertTrue(declaration != null, label + " call lost its exact selected declaration");
		final parameterTypes = declaration.getSignature().getArgs();
		assertTrue(parameterTypes.length == 1 && parameterTypes[0].getSemanticKey() == "primitive:Float",
			label + " call did not retain its declared Float parameter");
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
		return count;
	}

	static function main():Void {
		final root = haxe.io.Path.normalize(".tmp/m14_hxhx_stage3_dynamic_float_boundary");
		final sourceDir = haxe.io.Path.join([root, "src"]);
		final outDir = haxe.io.Path.join([root, "out"]);
		final invalidOutDir = haxe.io.Path.join([root, "out_invalid"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		FileSystem.createDirectory(sourceDir);

		final sourcePath = haxe.io.Path.join([sourceDir, "DynamicFloatBoundary.hx"]);
		final source = [
			"class DynamicFloatBoundary {",
			"  static function observed(value:Dynamic):Dynamic {",
			"    Sys.println('read=' + value);",
			"    return value;",
			"  }",
			"  static function takeFloat(value:Float):Float return value + 0.25;",
			"  static function takeDynamic(value:Dynamic):Dynamic return value;",
			"  static function direct(value:Dynamic):Float return takeFloat(observed(value));",
			"  static function guarded(value:Dynamic):Float {",
			"    return switch (Type.typeof(value)) {",
			"      case TFloat, TInt: takeFloat(value);",
			"      case _: takeFloat(-1);",
			"    };",
			"  }",
			"  static function concreteFloat():Float return takeFloat(2.5);",
			"  static function concreteInt():Float return takeFloat(2);",
			"  static function keepDynamic(value:Dynamic):Dynamic return takeDynamic(value);",
			"  static function main():Void {",
			"    Sys.println(direct(1.5));",
			"    Sys.println(direct(2));",
			"    Sys.println(concreteFloat());",
			"    Sys.println(concreteInt());",
			"    Sys.println(keepDynamic('text'));",
			"  }",
			"}",
		].join("\n");
		File.saveContent(sourcePath, source);
		File.saveContent(haxe.io.Path.join([sourceDir, "DynamicFloatProbe.hx"]), [
			"import haxe.macro.Context;",
			"import haxe.macro.Type;",
			"import haxe.macro.TypeTools;",
			"import haxe.macro.TypedExprTools;",
			"class DynamicFloatProbe {",
			"  public static macro function verify():Void {",
			"    final owner = switch Context.getType('DynamicFloatBoundary') {",
			"      case TInst(reference, _): reference.get();",
			"      case other: Context.fatalError('expected class, got ' + TypeTools.toString(other), Context.currentPos());",
			"    };",
			"    for (name in ['direct', 'guarded']) {",
			"      final field = owner.statics.get().filter(candidate -> candidate.name == name)[0];",
			"      final expression = field.expr();",
			"      if (expression == null) Context.fatalError('missing expression for ' + name, field.pos);",
			"      var found = false;",
			"      function walk(value:haxe.macro.Type.TypedExpr):Void {",
			"        switch value.expr {",
			"          case TCall(callee, arguments):",
			"            switch callee.expr {",
			"              case TField(_, FStatic(_, called)) if (called.get().name == 'takeFloat'):",
			"                if (TypeTools.toString(arguments[0].t) == 'Dynamic') {",
			"                  found = true;",
			"                  if (TypeTools.toString(value.t) != 'Float')",
			"                    Context.fatalError(name + ' call must be Float, got ' + TypeTools.toString(value.t), value.pos);",
			"                }",
			"              case _:",
			"            }",
			"          case _:",
			"        }",
			"        TypedExprTools.iter(value, walk);",
			"      }",
			"      walk(expression);",
			"      if (!found) Context.fatalError('missing takeFloat call in ' + name, field.pos);",
			"    }",
			"  }",
			"}",
		].join("\n"));

		final upstreamVersion = run("haxe", ["--version"]);
		assertTrue(upstreamVersion.exitCode == 0 && StringTools.trim(upstreamVersion.stdout) == "4.3.7",
			"the Dynamic Float oracle must be upstream Haxe 4.3.7: " + upstreamVersion.stdout + upstreamVersion.stderr);
		final upstream = run("haxe", [
			"-cp",
			sourceDir,
			"-main",
			"DynamicFloatBoundary",
			"--interp",
			"--macro",
			"DynamicFloatProbe.verify()"
		]);
		final expected = "read=1.5\n1.75\nread=2\n2.25\n2.75\n2.25\ntext\n";
		assertTrue(upstream.exitCode == 0, "Haxe 4.3.7 rejected the Dynamic Float contract: " + upstream.stderr);
		assertTrue(upstream.stdout == expected, "unexpected Haxe 4.3.7 Dynamic Float output: " + upstream.stdout);

		final parsed = ParserStage.parse(source, sourcePath);
		final resolved = new ResolvedModule("DynamicFloatBoundary", sourcePath, parsed);
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader([sourceDir], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index, loader);
		assertDynamicFloatCall(findFunctionCall(findFunction(typed, "DynamicFloatBoundary", "direct"), "takeFloat"), "direct");
		assertDynamicFloatCall(findFunctionCall(findFunction(typed, "DynamicFloatBoundary", "guarded"), "takeFloat"), "guarded");

		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), outDir, true);
		final generated = File.getContent(haxe.io.Path.join([outDir, "DynamicFloatBoundary.ml"]));
		assertTrue(countOccurrences(generated, "HxDynamic.floatValue") == 2,
			"Dynamic Float arguments did not use exactly the two checked call boundaries: " + generated);
		assertTrue(generated.indexOf("takeFloat (float_of_int 2)") >= 0, "a concrete Int argument lost its ordinary Float widening: " + generated);
		assertTrue(generated.indexOf("takeDynamic (value)") >= 0, "a Dynamic parameter call gained an unrelated Float conversion: " + generated);
		final nativeResult = run(executable, []);
		assertTrue(nativeResult.exitCode == 0, "native Dynamic Float executable failed: " + nativeResult.stderr);
		assertTrue(nativeResult.stdout == expected, "native Dynamic Float output differs from Haxe 4.3.7: " + nativeResult.stdout);

		final invalidSourcePath = haxe.io.Path.join([sourceDir, "InvalidDynamicFloat.hx"]);
		final invalidSource = [
			"class InvalidDynamicFloat {",
			"  static function observed(value:Dynamic):Dynamic {",
			"    Sys.println('invalid-read=' + value);",
			"    return value;",
			"  }",
			"  static function takeFloat(value:Float):Float return value;",
			"  static function main():Void {",
			"    Sys.println(takeFloat(observed('text')));",
			"  }",
			"}",
		].join("\n");
		File.saveContent(invalidSourcePath, invalidSource);
		final invalidTyped = TyperStage.typeModule(ParserStage.parse(invalidSource, invalidSourcePath));
		final invalidExecutable = EmitterStage.emitToDir(MacroStage.expandProgram([invalidTyped], []), invalidOutDir, true);
		final invalidResult = run(invalidExecutable, []);
		assertTrue(invalidResult.exitCode != 0, "a non-numeric Dynamic value unexpectedly entered Float");
		assertTrue(invalidResult.stdout == "invalid-read=text\n", "the rejected Dynamic argument was not evaluated exactly once: " + invalidResult.stdout);
		assertTrue(invalidResult.stderr.indexOf("Invalid Dynamic Float conversion operand; expected Int or Float") >= 0,
			"the rejected Dynamic argument did not report the checked Float diagnostic: " + invalidResult.stderr);
		deleteRecursive(root);
	}
}
