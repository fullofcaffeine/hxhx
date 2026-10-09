import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;
import backend.BackendContext;
import backend.BackendRegistry;
import backend.GenIrProgram;
import backend.source.PhpTypedProgramProjection;
import haxe.ds.StringMap;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

/** Compare real nested-function execution with upstream behavior, including shared captured storage. */
class M14PhpFunctionControlTest {
	static final sourceRoot = "test/oracle/php_function_control_seed/src";

	static function run(command:String, args:Array<String>):String {
		final child = new Process(command, args);
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		if (code != 0)
			throw command + " failed: " + stderr;
		return StringTools.replace(stdout, "\r\n", "\n");
	}

	/** Real PHP declarations resolve signature types; only the authored module is emitted. */
	static function program(name:String = "Main"):GenIrProgram {
		final arguments = Stage1Args.parse(["-cp", sourceRoot, "-main", name], true);
		if (arguments == null)
			throw "PHP function-control arguments did not parse";
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: Stage1Args.getExplicitClassPaths(arguments),
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(arguments),
			targetDefine: "php"
		});
		final defines = Stage3SetupSupport.buildDefinesMap([], "php", "php-native");
		final modules = ResolverStage.parseProjectRoots(paths, [name], defines);
		final index = TyperIndex.buildHeaders(modules);
		final loader = new ModuleLoader(paths, defines, index);
		loader.markResolvedAlready(modules);
		final selected = modules.filter(module -> ResolvedModule.getModulePath(module) == name);
		if (selected.length != 1)
			throw "PHP function-control fixture lost its source module";
		final typed = TyperStage.typeResolvedModule(selected[0], index, loader, true);
		return MacroStage.expandProgram([typed], []);
	}

	static function reject(action:Void->Void, expected:String):Void {
		try
			action()
		catch (error:String) {
			if (error.indexOf(expected) >= 0)
				return;
			throw "unexpected closure rejection: " + error;
		}
		throw "expected closure rejection: " + expected;
	}

	/** Equal-looking syntax and another compilation cannot authorize capture decisions. */
	static function checkOwnership():Void {
		final input = program();
		final projection = new PhpTypedProgramProjection(input);
		final main = projection.requireMain("Main").main;
		final storage = projection.requireFunctionLoweringPlan(main.getDeclaration()).getCaptureStorage();
		final original = main.requireCaptureCatalog().getExpressions()[0];
		storage.requireClosure(original);
		final copy:HxExpr = switch original {
			case ELambda(arguments, body, signature): ELambda(arguments.copy(), body, signature);
			case _: throw "closure fixture lost its lambda";
		};
		reject(() -> {
			storage.requireClosure(copy);
		}, "not an exact occurrence");
		final other = new PhpTypedProgramProjection(program()).requireMain("Main").main.requireCaptureCatalog().getExpressions()[0];
		reject(() -> {
			storage.requireClosure(other);
		}, "not an exact occurrence");
		switch original {
			case ELambda(arguments, _):
				arguments.push("changed");
				reject(() -> {
					storage.requireClosure(original);
				}, "projection was mutated");
				arguments.pop();
			case _:
				throw "closure fixture lost its lambda";
		}
		storage.requireClosure(original);
		final body = main.getBody();
		final copied = backend.source.SourceFunctionBodyRewriter.bodyWithOriginal(body,
			(node, rebuilt) -> TypedRuntimeTypeSource.isMarker(node) ? node : rebuilt);
		body.resize(0);
		for (statement in copied)
			body.push(statement);
		final root = ".tmp/m14_php_copied_closure_" + Std.string(Date.now().getTime());
		for (previous in [false, true]) {
			final output = root + (previous ? "_previous" : "_new");
			final artifact = output + "/index.php";
			if (previous) {
				FileSystem.createDirectory(output);
				File.saveContent(artifact, "previous-output\n");
			}
			reject(() -> {
				BackendRegistry.requireForTarget("php-native").emit(input, new BackendContext(output, null, "Main", true, false, new StringMap<String>()));
			}, "occurrence");
			if (previous) {
				if (File.getContent(artifact) != "previous-output\n" || FileSystem.readDirectory(output).length != 1)
					throw "copied PHP closure changed existing output";
			} else if (FileSystem.exists(output))
				throw "copied PHP closure published output";
		}
		Sys.println("PHP_FUNCTION_CONTROL_PUBLICATION:PASS");
		main.getBody().resize(0);
		reject(() -> {
			storage.requireClosure(original);
		}, "projection was mutated");
		Sys.println("PHP_FUNCTION_CONTROL_OWNERSHIP:PASS");
	}

	static function exercise(name:String, expectation:String):Void {
		final expected = File.getContent("test/oracle/php_function_control_seed/" + expectation);
		final upstream = run("haxe", ["-cp", sourceRoot, "-main", name, "--interp"]);
		if (upstream != expected)
			throw "upstream function-control behavior differs from the authored expectation:\n" + upstream;
		Sys.println("PHP_FUNCTION_CONTROL_UPSTREAM:PASS");
		final output = ".tmp/m14_php_function_control_" + name + "_" + Std.string(Date.now().getTime());
		final result = BackendRegistry.requireForTarget("php-native")
			.emit(program(name), new BackendContext(output, null, name, true, false, new StringMap<String>()));
		final actual = run("php", [result.entryPath]);
		if (actual != expected)
			throw "native PHP function-control behavior differs from upstream:\n" + actual;
		Sys.println("PHP_FUNCTION_CONTROL:PASS native");
	}

	static function main():Void {
		checkOwnership();
		exercise("Main", "expected.stdout");
		exercise("FieldClosures", "fields.stdout");
	}
}
