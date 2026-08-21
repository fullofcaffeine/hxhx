import haxe.ds.StringMap;
import sys.FileSystem;
import sys.io.File;
import TypedExpr.TypedExprTag;

/**
	Verifies that an explicit cast from a String-backed abstract reaches OCaml.

	The Haxe source selects a String method only after `(value : String)`. The
	typed tree must retain that conversion, and generated OCaml must recover a
	concrete `string` before it calls the String runtime helper.
**/
class M14HxhxStage3StringAbstractCastIntegrationTest {
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

	static function findFunction(module:TypedModule, className:String, functionName:String):TypedFunction {
		for (typedClass in module.getTypedClasses())
			if (HxClassDecl.getName(typedClass.getSourceDeclaration()) == className)
				for (typedFunction in typedClass.getFunctions())
					if (HxFunctionDecl.getName(typedFunction.getSourceDeclaration()) == functionName)
						return typedFunction;
		throw "missing " + className + "." + functionName;
	}

	static function findTag(expression:TypedExpr, tag:TypedExprTag):Null<TypedExpr> {
		if (expression.getTag() == tag)
			return expression;
		for (child in expression.getExpressions()) {
			final found = findTag(child, tag);
			if (found != null)
				return found;
		}
		return null;
	}

	static function main():Void {
		final sourcePath = "checks/StringAbstractCast.hx";
		final source = [
			"enum abstract TextPosition(String) from String to String {",
			"  final Top = 'top';",
			"}",
			"class StringAbstractCast {",
			"  public static function normalize(value:TextPosition):String {",
			"    return (value : String).toLowerCase();",
			"  }",
			"  static function main():Void {",
			"    Sys.println(normalize('MiXeD'));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(source, sourcePath);
		final resolved = new ResolvedModule("StringAbstractCast", sourcePath, parsed);
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader(["checks"], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index, loader);
		final normalize = findFunction(typed, "StringAbstractCast", "normalize");
		final returnExpression = normalize.getBody().getStatements()[0].getExpressions()[0];
		final typedCast = findTag(returnExpression, TypedExprTag.Cast);
		assertTrue(typedCast != null, "typed String method receiver lost its explicit cast");
		assertTrue(typedCast.getTexts().length == 1
			&& typedCast.getTexts()[0] == "String"
			&& typedCast.getType().getSemanticKey() == "primitive:String",
			"typed String method receiver lost its exact String destination");

		final projectedCall = TypedBodySource.expression(returnExpression);
		switch (projectedCall) {
			case ECall(EField(ECast(EIdent("value"), "String"), "toLowerCase"), []):
			case _:
				throw "typed source projection lost the explicit String receiver cast";
		}

		final tmpRoot = haxe.io.Path.normalize(".tmp/m14_hxhx_stage3_string_abstract_cast_" + Std.string(Date.now().getTime()));
		final outDir = haxe.io.Path.join([tmpRoot, "out"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), outDir, true);
		final output = File.getContent(haxe.io.Path.join([outDir, "StringAbstractCast.ml"]));
		assertTrue(output.indexOf("HxString.toLowerCase ((Obj.obj (Obj.repr (value)) : string)) ()") >= 0,
			"OCaml emission did not recover the concrete String carrier at the explicit cast");
		assertTrue(backend.ocaml.OcamlExplicitStringCast.render("Int", "value") == null, "String cast lowering changed an unrelated explicit cast");
		final result = new sys.io.Process(executable, []);
		final stdout = result.stdout.readAll().toString();
		final stderr = result.stderr.readAll().toString();
		final exitCode = result.exitCode();
		result.close();
		assertTrue(exitCode == 0, "String-backed abstract cast executable failed: " + stderr);
		assertTrue(stdout == "mixed\n", "String-backed abstract cast changed runtime behavior: " + stdout);
		deleteRecursive(tmpRoot);
	}
}
