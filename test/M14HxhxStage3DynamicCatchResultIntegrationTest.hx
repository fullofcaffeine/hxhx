import haxe.ds.StringMap;
import sys.FileSystem;
import sys.io.File;
import TypedExpr.TypedExprTag;

/**
	Verifies that try/catch control flow keeps concrete result evidence.

	Haxe selects the successful branch's concrete type when a `Dynamic` catch
	branch can flow into it. The typed tree must retain that decision and expose
	the catch conversion before OCaml requires both `HxRuntime.hx_try` closures
	to return the same representation. An unresolved statement-level return is
	also provisional: a later concrete return can still determine the function's
	result, while a real `Dynamic` return stays `Dynamic`.
**/
class M14HxhxStage3DynamicCatchResultIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertNotContains(text:String, unexpected:String, message:String):Void {
		if (text.indexOf(unexpected) >= 0)
			throw message + ": " + unexpected;
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

	static function findFunction(module:TypedModule, className:String, functionName:String):TypedFunction {
		for (typedClass in module.getTypedClasses())
			if (HxClassDecl.getName(typedClass.getSourceDeclaration()) == className)
				for (typedFunction in typedClass.getFunctions())
					if (HxFunctionDecl.getName(typedFunction.getSourceDeclaration()) == functionName)
						return typedFunction;
		throw "missing " + className + "." + functionName;
	}

	static function resultInitializer(functionDeclaration:TypedFunction):TypedExpr {
		for (statement in functionDeclaration.getBody().getStatements())
			if (statement.getTag() == TypedStmt.TypedStmtTag.Var
				&& statement.getNames().length > 0
				&& statement.getNames()[0] == "result"
				&& statement.getExpressions().length == 1)
				return statement.getExpressions()[0];
		throw "missing typed result initializer";
	}

	static function findCallNamed(expression:TypedExpr, name:String):Null<TypedExpr> {
		if (expression.getTag() == TypedExprTag.Call) {
			final children = expression.getExpressions();
			if (children.length > 0
				&& children[0].getTag() == TypedExprTag.NameRead
				&& children[0].getTexts().length == 1
				&& children[0].getTexts()[0] == name)
				return expression;
		}
		for (child in expression.getExpressions()) {
			final found = findCallNamed(child, name);
			if (found != null)
				return found;
		}
		return null;
	}

	static function findFunctionCallNamed(functionDeclaration:TypedFunction, name:String):Null<TypedExpr> {
		for (statement in functionDeclaration.getBody().getStatements())
			for (expression in statement.getExpressions()) {
				final found = findCallNamed(expression, name);
				if (found != null)
					return found;
			}
		return null;
	}

	static function catchBody(tryCall:TypedExpr):TypedExpr {
		final callChildren = tryCall.getExpressions();
		assertTrue(callChildren.length == 4, "structural try call lost its three arguments");
		final catches = callChildren[2];
		assertTrue(catches.getTag() == TypedExprTag.ArrayDecl
			&& catches.getExpressions().length == 1, "structural try call lost its catch list");
		final catchEntry = catches.getExpressions()[0];
		assertTrue(catchEntry.getTag() == TypedExprTag.ArrayDecl && catchEntry.getExpressions().length == 3,
			"structural catch entry lost its metadata or handler");
		final handler = catchEntry.getExpressions()[2];
		assertTrue(handler.getTag() == TypedExprTag.Lambda
			&& handler.getExpressions().length == 1, "structural catch entry lost its handler lambda");
		return handler.getExpressions()[0];
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

	static function run(command:String, arguments:Array<String>):{exitCode:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final exitCode = process.exitCode();
		process.close();
		return {exitCode: exitCode, stdout: stdout, stderr: stderr};
	}

	static function main():Void {
		final sourcePath = "checks/DynamicCatchResult.hx";
		final source = [
			"class DynamicCatchResult {",
			"  public static function fallback(error:Dynamic):Dynamic return 'caught';",
			"  public static function read(shouldFail:Bool):String {",
			"    final result = try { if (shouldFail) throw 'boom'; 'ready'; } catch(error:Dynamic) fallback(error);",
			"    return result;",
			"  }",
			"  public static function keepDynamic(value:Dynamic):Dynamic {",
			"    final result = try value catch(error:Dynamic) fallback(error);",
			"    return result;",
			"  }",
			"  public static function inferredStatementResult(value:Dynamic) {",
			"    try return Std.string(value) catch(error:Dynamic) {}",
			"    return 'fallback';",
			"  }",
			"  public static function inferredDynamicResult(value:Dynamic) {",
			"    try return value catch(error:Dynamic) {}",
			"    return value;",
			"  }",
			"  public static function unrelatedTry(value:Dynamic):Void {",
			"    try { if (value == null) throw 'missing'; } catch(error:Dynamic) {}",
			"  }",
			"  static function main():Void {",
			"    Sys.println(read(false));",
			"    Sys.println(read(true));",
			"    Sys.println('result=' + inferredStatementResult('statement'));",
			"  }",
			"}",
		].join("\n");
		final tmpRoot = haxe.io.Path.normalize(".tmp/m14_hxhx_stage3_dynamic_catch_result_" + Std.string(Date.now().getTime()));
		final sourceDir = haxe.io.Path.join([tmpRoot, "src"]);
		final outDir = haxe.io.Path.join([tmpRoot, "out"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		FileSystem.createDirectory(sourceDir);
		final fixturePath = haxe.io.Path.join([sourceDir, "DynamicCatchResult.hx"]);
		File.saveContent(fixturePath, source);
		File.saveContent(haxe.io.Path.join([sourceDir, "ReturnTypeProbe.hx"]), [
			"import haxe.macro.Context;",
			"import haxe.macro.Type;",
			"import haxe.macro.TypeTools;",
			"class ReturnTypeProbe {",
			"  public static macro function verify():Void {",
			"    final owner = switch Context.getType('DynamicCatchResult') {",
			"      case TInst(reference, _): reference.get();",
			"      case other: Context.fatalError('expected class, got ' + TypeTools.toString(other), Context.currentPos());",
			"    };",
			"    final field = owner.statics.get().filter(candidate -> candidate.name == 'inferredStatementResult')[0];",
			"    final result = switch Context.follow(field.type) {",
			"      case TFun(_, exactResult): Context.follow(exactResult);",
			"      case other: Context.fatalError('expected function, got ' + TypeTools.toString(other), field.pos);",
			"    };",
			"    if (TypeTools.toString(result) != 'String')",
			"      Context.fatalError('expected inferred String, got ' + TypeTools.toString(result), field.pos);",
			"  }",
			"}",
		].join("\n"));
		final upstreamVersion = run("haxe", ["--version"]);
		assertTrue(upstreamVersion.exitCode == 0 && StringTools.trim(upstreamVersion.stdout) == "4.3.7",
			"the return-inference oracle must be upstream Haxe 4.3.7: " + upstreamVersion.stdout + upstreamVersion.stderr);
		final upstream = run("haxe", [
			"-cp",
			sourceDir,
			"-main",
			"DynamicCatchResult",
			"--interp",
			"--macro",
			"ReturnTypeProbe.verify()"
		]);
		assertTrue(upstream.exitCode == 0, "upstream Haxe rejected the inferred String contract: " + upstream.stderr);
		assertTrue(upstream.stdout == "ready\ncaught\nresult=statement\n", "upstream Haxe produced unexpected output: " + upstream.stdout);

		final parsed = ParserStage.parse(source, sourcePath);
		final resolved = new ResolvedModule("DynamicCatchResult", sourcePath, parsed);
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader(["checks"], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index, loader);

		final expression = resultInitializer(findFunction(typed, "DynamicCatchResult", "read"));
		final structuralTry = findCallNamed(expression, "__hxhx_try");
		assertTrue(structuralTry != null, "read lost its structural try expression");
		assertTrue(structuralTry.getType().getSemanticKey() == "primitive:String",
			"read did not select the successful branch's String result: " + structuralTry.getType().getSemanticKey());
		final handlerBody = catchBody(structuralTry);
		assertTrue(handlerBody.getTag() == TypedExprTag.Cast
			&& handlerBody.getType().getSemanticKey() == "primitive:String"
			&& handlerBody.getExpressions()[0].getType().isDynamic(),
			"read did not retain the Dynamic-to-String catch conversion");

		final dynamicExpression = resultInitializer(findFunction(typed, "DynamicCatchResult", "keepDynamic"));
		final dynamicTry = findCallNamed(dynamicExpression, "__hxhx_try");
		assertTrue(dynamicTry != null && dynamicTry.getType().isDynamic(), "genuine Dynamic try expression changed its static result");
		assertTrue(catchBody(dynamicTry).getTag() != TypedExprTag.Cast, "genuine Dynamic catch branch gained a concrete conversion");
		final inferredStatementResult = findFunction(typed, "DynamicCatchResult", "inferredStatementResult");
		assertTrue(inferredStatementResult.getEnvironment().getReturnType().getDisplay() == "String",
			"statement-level try returns did not preserve the later concrete String result");
		final typedCallerResult = findFunctionCallNamed(findFunction(typed, "DynamicCatchResult", "main"), "inferredStatementResult");
		assertTrue(typedCallerResult != null && typedCallerResult.getType().getDisplay() == "String",
			"the typed caller did not consume the inferred function result as String");
		final inferredDynamicResult = findFunction(typed, "DynamicCatchResult", "inferredDynamicResult");
		assertTrue(inferredDynamicResult.getEnvironment().getReturnType().isDynamic(), "a genuinely Dynamic statement-level return was narrowed");
		final unrelatedTry = findFunction(typed, "DynamicCatchResult", "unrelatedTry");
		assertTrue(unrelatedTry.getEnvironment().getReturnType().getDisplay() == "Void", "an unrelated try/catch statement changed its explicit Void result");

		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), outDir, true);
		final output = File.getContent(haxe.io.Path.join([outDir, "DynamicCatchResult.ml"]));
		final catchCast = "(Obj.obj (Obj.repr (fallback (error))) : string)";
		assertTrue(countOccurrences(output, catchCast) == 1, "OCaml emission did not convert exactly the concrete String catch result: " + output);
		assertTrue(output.indexOf("inferredStatementResult (value : Obj.t) : string") >= 0,
			"OCaml emission lost the inferred String function result: " + output);
		assertNotContains(output, "Obj.obj (Obj.repr (inferredStatementResult", "the String caller gained an unchecked target-side result repair");
		final result = run(executable, []);
		assertTrue(result.exitCode == 0, "Dynamic catch result executable failed: " + result.stderr);
		assertTrue(result.stdout == upstream.stdout, "native try/catch output differs from upstream Haxe: " + result.stdout);
		deleteRecursive(tmpRoot);
	}
}
