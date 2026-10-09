import backend.BackendContext;
import backend.js.JsBackend;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Named extern calls use the resolved standard rest container, including its imported alias. */
class M14NamedRestMethodTest {
	static function check(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function run(command:String, arguments:Array<String>):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	static function main():Void {
		final root = ".tmp/named_rest_method";
		sys.FileSystem.createDirectory(root);
		final declarations = 'import haxe.extern.Rest as Tail; @:native("Math") extern class Numbers {@:overload(function(prefix:String, values:Tail<String>):Int {}) public static function max(prefix:Int, values:Tail<Int>):Int;}'
			+ 'typedef LocalTail<T>=Array<T>; extern class Fixed {public static function take(values:LocalTail<Int>):Int;}'
			+ '@:native("console") extern class Console {public static function log(value:String):Void;}';
		final source = declarations
			+
			'class Main {static function main():Void {Console.log(""+Numbers.max(0)); Console.log(""+Numbers.max(0,2,7)); var values=[2,7]; Console.log(""+Numbers.max(0,...values));}}';
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		final upstream = run("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
		check(upstream.code == 0, upstream.stderr);
		final expected = "0\n7\n7\n";
		check(run("node", [root + "/upstream.js"]).stdout == expected, "upstream rest result differs");
		final arguments = Stage1Args.parse(["-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [root],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(arguments),
			targetDefine: "js"
		});
		final defines = Stage3SetupSupport.buildDefinesMap([], "js", "js-native");
		final roots = ResolverStage.parseProjectRootsShallow(paths, ["Main"], defines);
		final index = TyperIndex.buildHeaders(roots);
		final loader = new ModuleLoader(paths, defines, index, null, false);
		loader.markResolvedAlready(roots);
		final fixed = index.getByFullName("Main.Fixed");
		check(!fixed.staticMethod("take").getArgRest()[0], "local Array alias became variadic");
		final typed = TyperStage.typeResolvedModule(roots[0], index);
		var selectedCalls = 0;
		function inspect(expression:TypedExpr):Void {
			final declaration = expression.getDeclaration();
			if (expression.getTag() == Call && declaration != null && declaration.getSignature().getName() == "max") {
				selectedCalls++;
				check(expression.getType().getSemanticKey() == "primitive:Int", "selected rest result lost its type");
			}
			for (child in expression.getExpressions())
				inspect(child);
		}
		for (owner in typed.getTypedClasses())
			for (method in owner.getFunctions())
				for (statement in method.getBody().getStatements())
					for (expression in statement.getExpressions())
						inspect(expression);
		check(selectedCalls == 3, "rest calls did not retain exact selected declarations");
		new JsBackend().emit(new MacroExpandedProgram([typed], false), new BackendContext(root, root + "/native.js", "Main", true, false, defines));
		final native = run("node", [root + "/native.js"]);
		check(native.code == 0 && native.stdout == expected, "native named rest result differs: " + native.stderr);
		final invalid = declarations + 'class Main {static function main():Void {Numbers.max(0,"bad");}}';
		sys.io.File.saveContent(path, invalid);
		check(run("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/invalid.js"]).code != 0, "upstream accepted wrong rest element");
		var rejected = false;
		try {
			final bad = new ResolvedModule("Main", path, ParserStage.parse(invalid, path));
			TyperStage.typeResolvedModule(bad, index);
		} catch (_:TyperError) {
			rejected = true;
		}
		check(rejected, "wrong rest element accepted");
		Sys.println("NAMED_REST_METHOD:PASS");
	}
}
