/** Execute complete source Map.set methods against independent native lifetime and ordering observers. */
class M14CppMapSetTest {
	/** Require successful execution and the independently specified Boolean result. */
	static function observe(command:String, arguments:Array<String>):Void {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final error = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || error.length != 0 || output != "true\n")
			throw "normal Map.set execution differs: " + output + error;
	}

	static function rejected(action:Void->Void):Void {
		var failed = false;
		try
			action()
		catch (_:haxe.Exception)
			failed = true;
		if (!failed)
			throw "Map.set accepted foreign call facts";
	}

	static function main():Void {
		final floating = TyType.fromHintText("Float");
		for (source in ["Dynamic", "Bool", "String", "Null<Int>"])
			if (backend.cpp.CppManagedValueTransfer.supports(floating, TyType.fromHintText(source)))
				throw "unrelated Float storage conversion admitted: " + source;
		if (backend.cpp.CppManagedValueTransfer.supports(TyType.fromHintText("Int"), floating))
			throw "Float narrowing borrowed integer widening";
		final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/cpp_map_set_seed", mainModule: "MapWrite", requiredModules: ["haxe.ds.Map"]});
		final program = new backend.cpp.CppTypedProgramProjection(new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules,
			fixture.index), false));
		final classes = new backend.cpp.CppManagedClassStorage(program);
		var unrelated = false;
		for (fn in program.requireClass(program.requireClassIdentity("MapWrite.Other")).getFunctions())
			for (statement in fn.getBody())
				TypedBackendSourceWalk.statement(statement, expression -> {
					final call = fn.findInstanceCall(expression);
					if (call == null)
						return;
					unrelated = true;
					if (backend.cpp.CppManagedMapSet.selects(call))
						throw "unrelated set method selected Map storage";
					rejected(() -> backend.cpp.CppManagedMapSet.require(call, classes));
				}, _ -> {});
		if (!unrelated)
			throw "Map.set fixture lost its unrelated declaration control";
		final functions:Array<backend.cpp.CppManagedProgramEmitter.CppManagedProgramFunction> = [];
		var calls = 0;
		for (fn in program.requireClass(program.requireClassIdentity("MapWrite")).getFunctions()) {
			final name = fn.requireSemanticDeclaration().getSignature().getName();
			functions.push({projection: fn, rootSymbol: "generated_" + name, symbolPrefix: "hxhx_function_map_set_" + name});
			for (statement in fn.getBody())
				TypedBackendSourceWalk.statement(statement, expression -> {
					final call = fn.findInstanceCall(expression);
					if (!backend.cpp.CppManagedMapSet.selects(call))
						return;
					try
						backend.cpp.CppManagedMapSet.require(call, classes, null, classes.casts)
					catch (error:haxe.Exception) {
						throw new haxe.Exception(name
							+ ": "
							+ call.getReceiverType().getSemanticKey()
							+ " <- "
							+ [for (type in call.getArgumentTypes()) type.getSemanticKey()].join(", "),
							error);
					}
					calls++;
					rejected(() -> call.assertCurrent("foreign", fn.getBodyRevision()));
					switch expression {
						case ECall(callee, arguments):
							if (fn.findInstanceCall(ECall(callee, arguments.copy())) != null)
								throw "copied Map.set marker borrowed another occurrence";
							final original = arguments[0];
							arguments[0] = EString("foreign");
							rejected(() -> fn.findInstanceCall(expression));
							arguments[0] = original;
							if (fn.findInstanceCall(expression) != call) throw "restored Map.set lost its occurrence";
						case _: throw "Map.set call lost its projected marker";
					}
				}, _ -> {});
		}
		if (calls != 4)
			throw "Map.set fixture omitted a complete method";
		if (backend.cpp.CppManagedMapSet.selects(null))
			throw "missing call selected Map.set";
		final body = new backend.cpp.CppManagedProgramEmitter({
			functions: functions,
			output: [],
			classes: classes,
			casts: classes.casts
		}).render();
		final output = ".tmp/cpp-map-set";
		sys.FileSystem.createDirectory(output);
		new backend.cpp.CppManagedRuntime().publish(output);
		sys.io.File.saveContent(output + "/Generated.hpp", '#include "ManagedCallable.hpp"\n' + classes.render() + "\n" + body);
		program.assertCurrent();
		CppManagedAssertionFixture.sanitizers(output, "CPP_MAP_SET", "test/cpp_managed_heap/MapSetObserver.cpp", "Generated.hpp");
		final root = "test/oracle/cpp_map_set_seed";
		observe("haxe", ["-cp", root, "-main", "Normal", "--interp"]);
		final normal = CppResolvedFixture.load({sourceRoot: root, mainModule: "Normal", requiredModules: ["haxe.ds.Map", "Sys"]});
		final normalProgram = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(normal.modules, normal.index), false);
		final result = backend.cpp.CppTargetCore.emit(normalProgram,
			new backend.BackendContext(output + "/normal", null, "Normal", true, true, normal.defines));
		if (!result.builtExecutable)
			throw "Map.set requires normal native compilation";
		observe(result.entryPath, []);
		Sys.println("CPP_MAP_SET_NORMAL:PASS");
		Sys.println("CPP_MAP_SET:PASS");
	}
}
