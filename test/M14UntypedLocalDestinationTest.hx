import sys.io.File;

/** Written locals inside untyped keep their destination without rewriting the initializer's known type. */
class M14UntypedLocalDestinationTest {
	static function main():Void {
		final prefix = 'class Box<T>{public function new(){}}class Main{static function identity<T>(value:Box<T>):Box<T>{Sys.println("once");return value;}';
		final body = 'var source:Box<Int>=new Box<Int>();var result:Box<String>=identity(source);Sys.println(source==result);return result;';
		check("block", prefix
			+ 'static function convert():Box<String>{untyped {'
			+ body
			+ '}}static function main():Void{Sys.println(convert()!=null);}}',
			"once\ntrue\ntrue\n", true);
		check("typed_rejection", prefix
			+ 'static function convert():Box<String>{'
			+ body
			+ '}static function main():Void{Sys.println(convert()!=null);}}',
			null);
		check("shadow",
			prefix +
			'static function convert():Box<String>{untyped {var value:Box<Int>=new Box<Int>();var value:Box<String>=identity(value);return value;}}static function main():Void{Sys.println(convert()!=null);}}',
			"once\ntrue\n", true);
		check("omitted_argument",
			prefix +
			'static function convert():Box<String>{untyped {var value:Box<String>=new Box();return value;}}static function main():Void{Sys.println(convert()!=null);}}',
			"true\n");
		check("permission_restored",
			prefix +
			'static function convert():Box<String>{untyped {var inside:Box<String>=identity(new Box<Int>());}var outside:Box<String>=identity(new Box<Int>());return outside;}static function main():Void{Sys.println(convert()!=null);}}',
			null);
	}

	/** Upstream is the acceptance oracle; runtime output also proves the initializer runs only once. */
	static function check(name:String, source:String, expected:Null<String>, inspectBoundary:Bool = false):Void {
		final root = ".tmp/untyped_local_destination_" + name;
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		File.saveContent(path, source);
		final oracle = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]);
		final output = oracle.stdout.readAll().toString();
		final errors = oracle.stderr.readAll().toString();
		final code = oracle.exitCode();
		oracle.close();
		if (expected == null ? code == 0 || errors.indexOf("Int") < 0 || errors.indexOf("String") < 0 : code != 0 || output != expected)
			throw "upstream untyped destination differs: " + name + output + errors;
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		var typed:Null<TypedModule> = null;
		try {
			typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		} catch (error:TyperError) {
			if (expected != null || Std.string(error).indexOf("not compatible") < 0)
				throw error;
		}
		if (expected == null) {
			if (typed != null)
				throw "ordinary typed mismatch was accepted: " + name;
		} else {
			if (typed == null)
				throw "valid untyped destination was rejected";
			if (inspectBoundary) {
				var observed = 0;
				function inspect(node:TypedExpr):Void {
					final children = node.getExpressions();
					if (node.getTag() == Untyped
						&& children.length == 1
						&& node.getType().getSemanticKey() == "nominal:Main.Box<primitive:String>"
						&& children[0].getType().getSemanticKey() == "nominal:Main.Box<primitive:Int>")
						observed++;
					for (child in children)
						inspect(child);
				}
				for (cls in typed.getTypedClasses())
					for (fn in cls.getFunctions())
						for (statement in fn.getBody().getStatements())
							for (node in statement.getExpressions())
								inspect(node);
				if (observed != 1)
					throw "untyped destination erased the initializer or destination type";
			}
			JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		}
		Sys.println("UNTYPED_LOCAL_DESTINATION:PASS " + name);
	}
}
