/** Dynamic admits callable values without weakening concrete function signatures or overload preference. */
class M14FunctionDynamicArgumentTest {
	static function main():Void {
		// Dynamic is intentional: these observers exercise that source-language argument contract.
		final source = 'class Main {
static function accept(value:Dynamic):Bool {return value!=null;}
static function invoke(value:Void->Int):Int {return value();}
static function main():Void {
var callback:Void->Int=function():Int{return 7;};
Sys.println(accept(callback));
var erased:Dynamic=callback;Sys.println(invoke(erased));
var receiver:Dynamic->Bool=function(value:Dynamic):Bool{return value!=null;};
Sys.println(receiver(callback));
}}';
		final typed = check("runtime", source, true);
		JsRuntimeFixture.assertRuntime(typed, "Main", "true\n7\ntrue\n");
		@:privateAccess M14NekoClosureControlTest.assertSource("function_dynamic_argument", source, "true\n7\ntrue\n");
		final overloadModule = check("overload", 'extern class Api {
@:overload(function(value:Dynamic):String {})
public static function choose(value:Void->Int):Int;
}
class Main {static function main():Void {
var callback:Void->Int=function():Int{return 7;};
var result:Int=Api.choose(callback);
}}', true);
		var selected = 0;
		function inspect(expression:TypedExpr):Void {
			final declaration = expression.getDeclaration();
			if (expression.getTag() == Call && declaration != null && declaration.getSignature().getName() == "choose") {
				if (!declaration.getSignature().getArgs()[0].isFunction() || expression.getType().getSemanticKey() != "primitive:Int")
					throw "Dynamic overload displaced the concrete callable overload";
				selected++;
			}
			for (child in expression.getExpressions())
				inspect(child);
		}
		for (owner in overloadModule.getTypedClasses())
			for (fn in owner.getFunctions())
				for (statement in fn.getBody().getStatements())
					for (expression in statement.getExpressions())
						inspect(expression);
		if (selected != 1)
			throw "missing selected callable overload";
		for (destination in ["Int", "Int->Int", "Void->String"])
			check("reject_"
				+ destination.split("->").join("_"), 'class Main {
static function accept(value:'
				+ destination
				+ '):Void {}
static function main():Void {var callback:Void->Int=function():Int{return 7;};accept(callback);}
}', false);
		Sys.println("FUNCTION_DYNAMIC_ARGUMENT:PASS");
	}

	/** Compare source acceptance upstream before checking local typing; extern cases require no runtime implementation. */
	static function check(name:String, source:String, accepts:Bool):Null<TypedModule> {
		final root = ".tmp/function_dynamic_argument_" + name + "_" + Date.now().getTime();
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		final process = new sys.io.Process("haxe", ["-cp", root, "-main", "Main", "--no-output", "-neko", root + "/unused.n"]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if ((code == 0) != accepts)
			throw "upstream argument acceptance differs: " + name + ": " + output + errors;
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		try {
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			if (!accepts)
				throw "local typing accepted incompatible argument: " + name;
			return typed;
		} catch (error:TyperError) {
			if (accepts || error.message.indexOf("No compatible method signature for accept") < 0)
				throw error;
			return null;
		}
	}
}
