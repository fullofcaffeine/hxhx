import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Explicit Dynamic generic destinations preserve the caller's type and cannot supply a concrete type in reverse. */
class M14GenericDynamicAssignmentTest {
	static function main():Void {
		for (entry in [
			{
				name: "erased",
				expected: "Box<Dynamic>",
				actual: "Box<Int>",
				accepted: true
			},
			{
				name: "restored",
				expected: "Box<Int>",
				actual: "Box<Dynamic>",
				accepted: false
			},
			{
				name: "nested",
				expected: "Box<Array<Dynamic>>",
				actual: "Box<Array<Int>>",
				accepted: true
			},
			{
				name: "nested_reverse",
				expected: "Box<Array<Int>>",
				actual: "Box<Array<Dynamic>>",
				accepted: false
			},
			{
				name: "numeric",
				expected: "Box<Float>",
				actual: "Box<Int>",
				accepted: false
			},
			{
				name: "wrong",
				expected: "Box<String>",
				actual: "Box<Int>",
				accepted: false
			},
			{
				name: "array",
				expected: "Array<Dynamic>",
				actual: "Array<Int>",
				accepted: true
			},
			{
				name: "array_numeric",
				expected: "Array<Float>",
				actual: "Array<Int>",
				accepted: false
			},
			{
				name: "parameter",
				expected: "Box<Dynamic>",
				actual: "Box<T>",
				accepted: true
			}
		]) {
			final root = ".tmp/generic-dynamic-assignment-" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			final source = 'class Box<T>{}class Main{static function take(value:' + entry.expected + '):Void{}static function inspect'
				+ (entry.name == "parameter" ? '<T>' : '') + '(value:' + entry.actual + '):Void{take(value);}static function main():Void{}}';
			sys.io.File.saveContent(path, source);
			final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
			final process = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "--interp"]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if ((code == 0) != entry.accepted || (!entry.accepted && stderr.indexOf("should be") < 0))
				throw "upstream generic assignment differs: " + entry.name + stdout + stderr;
			final args = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
			final paths = Stage3SetupSupport.projectClassPaths({
				explicitPaths: [root],
				libraries: [],
				cwd: Sys.getCwd(),
				standardRoot: Stage1Args.getStandardLibraryRoot(args),
				targetDefine: "js"
			});
			final defines = Stage3SetupSupport.buildDefinesMap([], "js", "js-native");
			final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			final index = TyperIndex.buildHeaders([module]);
			final loader = new ModuleLoader(paths, defines, index, null, false);
			loader.markResolvedAlready([module]);
			var accepted = false;
			try {
				TyperStage.typeResolvedModule(module, index, loader, true).getBackendProjection();
				accepted = true;
			} catch (error:haxe.Exception) {
				if (entry.accepted)
					throw error;
			}
			if (accepted != entry.accepted)
				throw "local generic assignment differs: " + entry.name;
			Sys.println("GENERIC_DYNAMIC_ASSIGNMENT:PASS " + entry.name);
		}
		runtime();
	}

	/** Read a concrete stored value through a generic Dynamic parameter in generated JavaScript. */
	static function runtime():Void {
		final root = ".tmp/generic-dynamic-assignment-runtime";
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		final source = 'class Box<T>{public var value:T;public function new(value:T){this.value=value;}}'
			+ 'class Main{static function read(value:Box<Dynamic>):Dynamic{return value.value;}'
			+ 'static function forward<T>(value:Box<T>):Dynamic{return read(value);}'
			+ 'static function main():Void{var value=new Box<Int>(7);trace(forward(value));}}';
		sys.io.File.saveContent(path, source);
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		final process = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "--interp"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || !StringTools.endsWith(stdout, ": 7\n") || stderr.length != 0)
			throw "upstream generic runtime differs: " + stdout + stderr;
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		JsRuntimeFixture.assertRuntime(typed, "Main", "7\n");
		Sys.println("GENERIC_DYNAMIC_ASSIGNMENT_RUNTIME:PASS");
	}
}
