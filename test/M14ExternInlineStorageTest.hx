/** Inline parameter and local storage must preserve ordinary Haxe assignment rules and effects. */
class M14ExternInlineStorageTest {
	public static function run():Void {
		// Dynamic is authored at this boundary to exercise the language's implicit
		// assignment contract. The helper must still expose concrete Int storage.
		final source = '@:native("console") extern class Console {public static function log(value:String):Void;}
extern class Helper {
public static inline function typed(value:Int):Int{return value+1;}
public static inline function local(value:Dynamic):Int{var selected:Int=value;return selected+2;}
}
class Main {
static var effects=0;
static function input():Dynamic{effects++;return 4;}
static function main():Void {
Console.log(""+Helper.typed(input()));
Console.log(""+Helper.local(input()));
Console.log(""+effects);
}}';
		final expected = "5\n6\n2\n";
		final root = ".tmp/extern-inline-storage";
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		final upstream = @:privateAccess M14JsPlainExternBindingTest.run(compiler == null ? "node_modules/.bin/haxe" : compiler,
			["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
		if (upstream.code != 0)
			throw "upstream inline storage compilation failed: " + upstream.stderr;
		final observed = @:privateAccess M14JsPlainExternBindingTest.run("node", [root + "/upstream.js"]);
		if (observed.code != 0 || observed.stdout != expected)
			throw "upstream inline storage differs: " + observed.stdout + observed.stderr;
		Sys.println("EXTERN_INLINE_STORAGE_UPSTREAM:PASS");
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		var assignments = 0;
		function expression(value:TypedExpr):Void {
			if (value.getTag() == Cast
				&& value.getType().getCanonicalDisplay() == "Int"
				&& value.getExpressions()[0].getType().isDynamic()) {
				if (value.getTexts()[0] != "")
					throw "inline assignment introduced an authored checked cast";
				assignments++;
			}
			for (child in value.getExpressions())
				expression(child);
		}
		function statement(value:TypedStmt):Void {
			for (child in value.getExpressions())
				expression(child);
			for (child in value.getStatements())
				statement(child);
		}
		for (owner in typed.getTypedClasses())
			if (HxClassDecl.getName(owner.getSourceDeclaration()) == "Main")
				for (fn in owner.getFunctions())
					for (value in fn.getBody().getStatements())
						statement(value);
		if (assignments != 2)
			throw "inline storage lost its parameter or local assignment conversion";
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		Sys.println("EXTERN_INLINE_STORAGE:PASS");
	}

	static function main():Void
		run();
}
