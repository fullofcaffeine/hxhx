import backend.BackendContext;
import backend.source.SourceMvpTargetCore;

/** Observe initializer scope and publication independently of generated helper spelling. */
class M14PythonInitializerRegionsTest {
	static function typed(source:String):TypedModule {
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
	}

	static function observe(command:String, arguments:Array<String>):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	/** Declaration lookup must retain object ownership and detect mutated initializer syntax. */
	static function ownership(module:TypedModule, source:String):Void {
		final owner = HxModuleDecl.getClasses(module.getBackendDeclaration())[0];
		final fields = HxClassDecl.getFields(owner);
		final field = fields[1];
		final selected = module.findBackendFieldInitializer(owner, field);
		if (selected == null)
			throw "initializer lookup lost its exact field";
		final foreignOwner = HxModuleDecl.getClasses(typed(source).getBackendDeclaration())[0];
		if (module.findBackendFieldInitializer(foreignOwner, field) != null
			|| module.findBackendFieldInitializer(owner, HxClassDecl.getFields(foreignOwner)[1]) != null)
			throw "initializer lookup accepted a foreign declaration";
		switch selected.getExpression() {
			case ELoweredControl(Initializer(_), _, entries, _):
				entries.push(EInt(999));
				var rejected = false;
				try {
					module.findBackendFieldInitializer(owner, field);
				} catch (failure:haxe.Exception) {
					rejected = failure.message.indexOf("initializer projection was mutated") >= 0;
				}
				entries.pop();
				if (!rejected)
					throw "initializer lookup accepted mutated syntax";
			case _:
				throw "ownership observer requires a statement initializer";
		}
	}

	/** The typed source stays immutable while a separate Python view qualifies static members. */
	static function emit(module:TypedModule, root:String):String {
		final before = CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity();
		final result = SourceMvpTargetCore.emit(Python, new MacroExpandedProgram([module], false),
			new BackendContext(root, null, "Main", true, false, new haxe.ds.StringMap()));
		if (before != CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity())
			throw "Python initializer emission changed authored typed source";
		return result.entryPath;
	}

	static function main():Void {
		final source = "class Main { static var effects:Int = 0;"
			+ "static var first:Int = { var local = 1; local += 2; effects += 1; local; };"
			+ "static var getter:Void->Int = { var local = 17; () -> local; };"
			+ "static var second:Int = { var local = 9; effects += 1; local; };"
			+ "static function main():Void { Sys.println(first); Sys.println(second); Sys.println(effects); Sys.println(getter()); }}";
		final root = ".tmp/python-initializer-regions";
		sys.FileSystem.createDirectory(root);
		sys.io.File.saveContent(root + "/Main.hx", source);
		final expected = "3\n9\n2\n17\n";
		final upstream = observe("haxe", ["-cp", root, "--run", "Main"]);
		if (upstream.code != 0 || upstream.stdout != expected)
			throw "upstream initializer scope contract failed: " + upstream.stdout + upstream.stderr;
		final module = typed(source);
		ownership(module, source);
		final path = emit(module, root + "/scope");
		final native = observe("python3", [path]);
		if (native.code != 0 || native.stdout != expected || native.stderr != "")
			throw "Python initializer scopes differ: " + native.stdout + native.stderr;

		final throwing = "class Main { static var effects:Int = 0;"
			+ "static var failed:Int = { effects += 1; throw 'initializer-stop'; 7; };"
			+ "static var later:Int = { effects += 10; 99; }; static function main():Void {} }";
		sys.io.File.saveContent(root + "/Main.hx", throwing);
		final upstreamThrow = observe("haxe", ["-cp", root, "--run", "Main"]);
		if (upstreamThrow.code == 0 || (upstreamThrow.stdout + upstreamThrow.stderr).indexOf("initializer-stop") < 0)
			throw "upstream initializer did not stop on its throw";
		final throwingPath = emit(typed(throwing), root + "/throwing");
		// Keep the module namespace after the exception so an independent observer
		// can inspect defaults, completed effects, and skipped later initialization.
		final observer = "import sys\nscope = {'__name__': '__main__'}\n"
			+ "try:\n    exec(compile(open(sys.argv[1]).read(), sys.argv[1], 'exec'), scope)\n"
			+ "except Exception as failure:\n    assert 'initializer-stop' in str(failure), str(failure)\n"
			+ "else:\n    raise AssertionError('initializer did not throw')\n"
			+ "owner = scope['Main']\nassert owner.effects == 1\nassert owner.failed is None\nassert owner.later is None\n";
		sys.io.File.saveContent(root + "/observe.py", observer);
		final stopped = observe("python3", [root + "/observe.py", throwingPath]);
		if (stopped.code != 0 || stopped.stdout != "" || stopped.stderr != "")
			throw "Python published an aborted initializer: " + stopped.stdout + stopped.stderr;
		rejectStatementFunction(root);
		Sys.println("PYTHON_INITIALIZER_REGIONS:PASS");
	}

	/** Unsupported functions must preserve existing output and reject before dropping their effects. */
	static function rejectStatementFunction(root:String):Void {
		final source = "class Main { static function main():Void {"
			+ "var next = function(value:Int):Int { Sys.println('effect'); return value + 2; }; Sys.println(next(3)); }}";
		sys.io.File.saveContent(root + "/Main.hx", source);
		final upstream = observe("haxe", ["-cp", root, "--run", "Main"]);
		if (upstream.code != 0 || upstream.stdout != "effect\n5\n")
			throw "upstream statement function contract failed: " + upstream.stdout + upstream.stderr;
		final destination = root + "/rejected";
		sys.FileSystem.createDirectory(destination);
		final artifact = destination + "/Main.py";
		final sentinel = "existing output must survive rejected compilation\n";
		sys.io.File.saveContent(artifact, sentinel);
		var rejected = false;
		try {
			emit(typed(source), destination);
		} catch (failure:haxe.Exception) {
			rejected = failure.message.indexOf("Python expression function requires a single value return") >= 0;
		}
		if (!rejected || sys.io.File.getContent(artifact) != sentinel)
			throw "Python statement function lost its effects or replaced existing output";
		final position = HxPos.unknown();
		final malformed = HxExpr.ELoweredControl(FunctionBody, "outer", [HxExpr.ELoweredControl(Return, "foreign", [HxExpr.EInt(1)], position)], position);
		var rendered = false;
		var wrongReturnRejected = false;
		try {
			backend.source.PythonExpressionFunction.render("", malformed, value -> {
				rendered = true;
				return "1";
			});
		} catch (failure:haxe.Exception) {
			wrongReturnRejected = failure.message.indexOf("unsupported layout or destination") >= 0;
		}
		if (!wrongReturnRejected || rendered)
			throw "Python function accepted a foreign return destination";
	}
}
