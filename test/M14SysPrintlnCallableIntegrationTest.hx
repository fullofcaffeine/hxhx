import backend.BackendContext;
import backend.BackendRegistry;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Execute saved output functions without changing the callee-before-argument evaluation order. */
class M14SysPrintlnCallableIntegrationTest {
	/** Equal syntax and stale projections cannot authorize a host function binding. */
	static function proveOccurrenceOwnership(module:TypedModule):Void {
		final owner = module.getTypedClasses().filter(cls -> HxClassDecl.getName(cls.getSourceDeclaration()) == "Main")[0];
		final fn = owner.getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getSourceDeclaration()) == "main")[0];
		final projection = TypedBodySource.functionProjection(fn);
		final scope:backend.js.JsEmitScope = {
			resolveLocal: _ -> null,
			resolveClassRef: _ -> null,
			resolveSuperClassRef: () -> null,
			callableExpressions: projection.findCallableExpression
		};
		var output:Null<HxExpr> = null;
		var user:Null<HxExpr> = null;
		var mutableArguments:Null<Array<HxExpr>> = null;
		for (entry in projection.requireCaptureCatalog().getCallableExpressions()) {
			final declaration = entry.source.getDeclaration();
			if (entry.source.getTag() == FieldRead && declaration != null && declaration.getSignature().getName() == "println") {
				if (declaration.getOwner().getCanonicalName() == "Sys")
					output = entry.expression;
				else
					user = entry.expression;
			}
			switch entry.expression {
				case ECall(_, arguments):
					mutableArguments = arguments;
				case _:
			}
		}
		if (output == null || user == null || mutableArguments == null)
			throw "observer must contain both exact output owners and a mutable projected call";
		if (backend.js.JsIntrinsicCallable.emitValue(output, scope) != "console.log"
			|| backend.js.JsIntrinsicCallable.emitValue(user, scope) != null)
			throw "output binding must distinguish the selected standard-library declaration";
		final copy = switch output {
			case EField(receiver, name): HxExpr.EField(receiver, name);
			case _: throw "output observer lost its field value";
		};
		if (backend.js.JsIntrinsicCallable.emitValue(copy, scope) != null)
			throw "copied output syntax borrowed occurrence authority";
		final foreignScope:backend.js.JsEmitScope = {
			resolveLocal: scope.resolveLocal,
			resolveClassRef: scope.resolveClassRef,
			resolveSuperClassRef: scope.resolveSuperClassRef,
			callableExpressions: TypedBodySource.functionProjection(fn).findCallableExpression
		};
		if (backend.js.JsIntrinsicCallable.emitValue(output, foreignScope) != null)
			throw "another projection borrowed the output occurrence";
		mutableArguments.push(EInt(99));
		try {
			backend.js.JsIntrinsicCallable.emitValue(output, scope);
		} catch (error:haxe.Exception) {
			if (error.message.indexOf("projection was mutated") >= 0)
				return;
			throw error;
		}
		throw "mutated output projection retained callable authority";
	}

	static function main():Void {
		// Dynamic is the real Sys.println boundary signature. All observed inputs
		// are primitive values; ordinary application callbacks remain Int -> Void.
		final source = [
			"class Output {",
			"  public static var saved:Dynamic->Void = Sys.println;",
			"  public var instance:Dynamic->Void = Sys.println;",
			"  public function new() {}",
			"  public static function println(value:Int):Void Sys.println(value + 30);",
			"}",
			"class Main {",
			"  static var callback:Int->Void = first;",
			"  static var effects:Int = 0;",
			"  static function first(value:Int):Void Sys.println(value + 10);",
			"  static function second(value:Int):Void Sys.println(value + 20);",
			"  static function replace():Int { effects++; callback = second; return 7; }",
			"  static function main():Void {",
			"    var saved = Sys.println;",
			"    if (saved != Sys.println) throw 'output function identity changed';",
			"    saved('local');",
			"    Output.saved('static');",
			"    new Output().instance('instance');",
			"    var nested = function():Dynamic->Void return Sys.println;",
			"    nested()('nested');",
			"    var user = Output.println; user(3);",
			"    var prior = callback;",
			"    prior({ var value = replace(); value; });",
			"    callback(8);",
			"    if (effects != 1) throw 'argument evaluated more than once';",
			"    saved('done');",
			"  }",
			"}"
		].join("\n");
		final expected = "local\nstatic\ninstance\nnested\n33\n17\n28\ndone\n";
		final root = Path.join([Sys.getCwd(), ".tmp", "m14_sys_println_callable"]);
		FileSystem.createDirectory(root);
		final path = Path.join([root, "Main.hx"]);
		File.saveContent(path, source);
		M14Stage3RuntimeFixture.observe({command: "haxe", arguments: ["-cp", root, "-main", "Main", "--interp"], expected: expected});
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final index = TyperIndex.buildHeaders([resolved]);
		final standardRoot = hxhx.Stage1Compiler.Stage1Args.getStandardLibraryRoot(hxhx.Stage1Compiler.Stage1Args.parse(["-main", "Main"], true));
		final loader = new ModuleLoader([root, standardRoot], HxDefineMap.fromRawDefines(["sys"]), index);
		loader.markResolvedAlready([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index, loader);
		proveOccurrenceOwnership(typed);
		final program = new MacroExpandedProgram([typed], false);
		for (entry in [
			{target: "js-native", runtime: "node", extension: "js"},
			{target: "python-native", runtime: "python3", extension: "py"}
		]) {
			final output = Path.join([root, "main." + entry.extension]);
			final context = new BackendContext(root, output, "Main", true, false, new StringMap<String>());
			final emitted = BackendRegistry.createForTarget(entry.target).emit(program, context);
			M14Stage3RuntimeFixture.observe({command: entry.runtime, arguments: [emitted.entryPath], expected: expected});
		}
		Sys.println("SYS_PRINTLN_CALLABLE:PASS");
	}
}
