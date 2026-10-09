import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/**
	Compare native execution of C# unsafe regions with upstream Haxe.

	Real target headers select cs.Lib, while only the authored Main body is emitted.
	This focused contract does not replace full standard-library acceptance. A
	separate native observer invokes run() and prints its result, so an empty or
	placeholder generated main cannot make the runtime assertion pass.
 */
class M14CsSyntaxScopeTest {
	public static function main():Void {
		final root = ".tmp/cs_syntax_scope_" + Date.now().getTime();
		sys.FileSystem.createDirectory(root);
		final observer = root + "/Observe.cs";
		// Reflection is confined to the independent native test observer. Its exact
		// public zero-argument method selects authored behavior from either artifact.
		sys.io.File.saveContent(observer,
			"class Observe { static void Main(string[] args) { var assembly = System.Reflection.Assembly.LoadFrom(args[0]); var type = assembly.GetType(\"Main\") ?? assembly.GetType(\"haxe.root.Main\"); if(type == null) throw new System.Exception(\"missing Main\"); var method = type.GetMethod(\"run\", System.Type.EmptyTypes); if(method == null) throw new System.Exception(\"missing run\"); System.Console.WriteLine(method.Invoke(null, new object[0])); } }");
		run("mcs", ["-out:" + root + "/Observe.exe", observer]);
		final cases = [
			{name: "local_effect", body: "var result = 0; cs.Lib.unsafe({ result += 2; }); return result;", expected: "2"},
			{name: "early_return", body: "cs.Lib.unsafe({ return 7; }); return 9;", expected: "7"},
			{name: "alias", body: "var result = 0; Safety.unsafe({ result = 8; }); return result;", expected: "8"},
			{
				name: "loop_exits",
				body: "var sum = 0; for(i in 0...6) { cs.Lib.unsafe({ if(i == 1) continue; if(i == 4) break; sum += i; }); } return sum;",
				expected: "5"
			},
			{name: "nested_return", body: "cs.Lib.unsafe({ var f = function():Int { return 3; }; return f() + 4; }); return 9;", expected: "7"},
			{
				name: "sibling_locals",
				body: "var result = 0; cs.Lib.unsafe({ var value = 2; result += value; }); cs.Lib.unsafe({ var value = 3; result += value; }); return result;",
				expected: "5"
			}
		];
		for (entry in cases) {
			final directory = root + "/" + entry.name;
			sys.FileSystem.createDirectory(directory);
			final source = "import cs.Lib as Safety; class Main { public static function run():Int { " + entry.body + " } static function main() { run(); } }";
			sys.io.File.saveContent(directory + "/Main.hx", source);
			run("haxe", [
				"-cp",
				directory,
				"-main",
				"Main",
				"-cs",
				directory + "/upstream",
				"-D",
				"unsafe"
			]);
			expect(run("mono", [root + "/Observe.exe", directory + "/upstream/bin/Main.exe"]), entry.expected);
			final input = typed(directory);
			checkScopeOwnership(input.module);
			final result = backend.BackendRegistry.requireForTarget("cs-native")
				.emit(new MacroExpandedProgram([input.module], false),
					new backend.BackendContext(directory + "/candidate", null, "Main", true, true, input.defines));
			expect(run("mono", [root + "/Observe.exe", result.entryPath]), entry.expected);
			final emitted = sys.io.File.getContent(directory + "/candidate/src/__HxMain.cs");
			if (emitted.indexOf("unsafe\n") < 0)
				throw "C# syntax scope was erased";
			Sys.println("CS_SYNTAX_SCOPE:PASS " + entry.name);
		}
		checkInvalidCalls(root);
	}

	/** Typed rewrites cannot remove the body or change a statement scope into a value. */
	static function checkScopeOwnership(module:TypedModule):Void {
		var found = false;
		function expression(node:TypedExpr):Void {
			if (node.getTag() == TargetScope) {
				found = true;
				if (node.getDeclaration().getOwner().getCanonicalName() != "cs.Lib" || node.getNamedArguments() != null)
					throw "scope lost its exact API or acquired runtime argument binding";
				var rejected = false;
				try
					node.withExpressions([])
				catch (_:haxe.Exception)
					rejected = true;
				if (!rejected)
					throw "scope accepted a missing body";
				rejected = false;
				try
					node.withType(TyType.fromHintText("Int"))
				catch (_:haxe.Exception)
					rejected = true;
				if (!rejected)
					throw "scope accepted an ordinary result value";
			}
			for (child in node.getExpressions())
				expression(child);
		}
		function statement(node:TypedStmt):Void {
			for (value in node.getExpressions())
				expression(value);
			for (child in node.getStatements())
				statement(child);
		}
		for (owner in module.getTypedClasses())
			for (fn in owner.getFunctions())
				for (entry in fn.getBody().getStatements())
					statement(entry);
		if (!found)
			throw "fixture did not retain a typed syntax scope";
	}

	/** Ordinary and same-spelled user methods must still reject Void runtime arguments. */
	static function checkInvalidCalls(root:String):Void {
		final cases = [
			{name: "ordinary_void", declaration: "static function consume<T>(value:T):Void {}", call: "consume(effect())"},
			{name: "shadowed_name", declaration: "static function unsafe<T>(value:T):Void {}", call: "unsafe(effect())"},
			{name: "inline_wrapper", declaration: "extern static inline function wrap<T>(value:T):Void { untyped __unsafe__(value); }", call: "wrap(effect())"},
			{name: "missing_body", declaration: "", call: "cs.Lib.unsafe()"}
		];
		for (entry in cases) {
			final directory = root + "/" + entry.name;
			sys.FileSystem.createDirectory(directory);
			final source = "class Main { "
				+ entry.declaration
				+ " static function effect():Void {} static function main() { "
				+ entry.call
				+ "; } }";
			sys.io.File.saveContent(directory + "/Main.hx", source);
			run("haxe", [
				"-cp",
				directory,
				"-main",
				"Main",
				"-cs",
				directory + "/upstream",
				"-D",
				"unsafe",
				"-D",
				"no-compilation"
			], false);
			var diagnostic = "";
			try
				typed(directory).module.getBackendProjection()
			catch (error:haxe.Exception)
				diagnostic = error.message;
			if (diagnostic.length == 0)
				throw "candidate accepted invalid scope call: " + entry.name;
			if (entry.name != "missing_body" && diagnostic.indexOf("Void") < 0)
				throw "invalid runtime argument failed for an unrelated reason: " + diagnostic;
			Sys.println("CS_SYNTAX_SCOPE_NEGATIVE:PASS " + entry.name);
		}
	}

	/** Resolve real providers without claiming that their entire bodies pass typing. */
	static function typed(root:String):{module:TypedModule, defines:haxe.ds.StringMap<String>} {
		final args = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
		if (args == null)
			throw "fixture arguments did not parse";
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [root],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(args),
			targetDefine: "cs"
		});
		final defines = Stage3SetupSupport.buildDefinesMap(["unsafe"], "cs", "cs-native");
		final resolved = ResolverStage.parseProjectRoots(paths, ["Main"], defines);
		final index = TyperIndex.buildHeaders(resolved);
		final loader = new ModuleLoader(paths, defines, index, null, true);
		loader.markResolvedAlready(resolved);
		for (module in resolved)
			if (ResolvedModule.getModulePath(module) == "Main")
				return {module: TyperStage.typeResolvedModule(module, index, loader, true), defines: defines};
		throw "fixture Main was not resolved";
	}

	static function expect(actual:String, expected:String):Void {
		if (StringTools.trim(actual) != expected)
			throw "native scope result differs: " + actual + " expected " + expected;
	}

	static function run(command:String, arguments:Array<String>, expectSuccess:Bool = true):String {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final error = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if ((code == 0) != expectSuccess)
			throw command + " unexpected exit: " + output + error;
		return output;
	}
}
