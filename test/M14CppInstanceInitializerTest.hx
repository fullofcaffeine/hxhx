import backend.BackendContext;
import backend.cpp.CppTargetCore;
import backend.cpp.CppTypedProgramProjection;
import backend.cpp.CppManagedClassStorage;
import backend.cpp.CppManagedInstanceInitializer.render;
import backend.cpp.CppManagedExpressionLocals;

/** Execute authored initializer order and retained values under native collection and sanitizers. */
class M14CppInstanceInitializerTest {
	static function main():Void {
		final root = "test/oracle/cpp_instance_initializer_seed";
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		if (Sys.command(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "--interp"]) != 0)
			throw "upstream instance initialization contract differs";
		final path = root + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		assertOwnership(typed, path);
		final output = ".tmp/cpp-instance-initializer";
		final result = CppTargetCore.emit(new MacroExpandedProgram([typed], false),
			new BackendContext(output, null, "Main", true, true, new haxe.ds.StringMap()));
		if (!result.builtExecutable || Sys.command(result.entryPath, []) != 0)
			throw "instance initialization requires successful native execution";
		sys.io.File.copy("test/cpp_managed_heap/InheritedStorageObserver.cpp", output + "/Observer.cpp");
		final nativeCompiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		for (optimization in ["-O0", "-O2"]) {
			final executable = output + "/observer" + optimization;
			if (Sys.command(timeout, [
				"60",
				nativeCompiler,
				"-std=c++17",
				optimization,
				"-g",
				"-fno-omit-frame-pointer",
				"-fsanitize=address,undefined",
				'-DHXHX_INHERITED_PROGRAM="src/Main.cpp"',
				output + "/Observer.cpp",
				"-o",
				executable
			]) != 0 || Sys.command(timeout, ["30", executable]) != 0)
				throw "instance initialization failed its collecting sanitizer observer";
			Sys.println("CPP_INSTANCE_INITIALIZER:" + optimization + ":PASS");
		}
		final throwingRoot = "test/oracle/cpp_instance_initializer_throw_seed";
		if (Sys.command(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", throwingRoot, "-main", "Upstream", "--interp"]) != 0)
			throw "upstream throwing initializer contract differs";
		M14CppManagedStartupExecutionTest.runFixture({
			sourceRoot: throwingRoot,
			output: ".tmp/cpp-instance-initializer-throw",
			observer: "test/cpp_managed_heap/InstanceInitializerThrowObserver.cpp"
		});
		Sys.println("CPP_INSTANCE_INITIALIZER:THROW:PASS");
		final captureRoot = "test/oracle/cpp_instance_initializer_capture_seed";
		if (Sys.command(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", captureRoot, "-main", "Main", "--interp"]) != 0)
			throw "upstream captured initializer contract differs";
		M14CppManagedStartupExecutionTest.runFixture({
			sourceRoot: captureRoot,
			output: ".tmp/cpp-instance-initializer-capture",
			requiredModules: ["Array"],
			observer: "test/cpp_managed_heap/InstanceInitializerCaptureObserver.cpp"
		});
		Sys.println("CPP_INSTANCE_INITIALIZER:CAPTURE:PASS");
		Sys.println("CPP_INSTANCE_INITIALIZER:PASS");
	}

	/** Equal source text from another typing run cannot authorize a write, and projection mutations invalidate the owner. */
	static function assertOwnership(typed:TypedModule, path:String):Void {
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final storage = new CppManagedClassStorage(program);
		function selected(candidate:CppTypedProgramProjection, name:String = "a"):TypedBackendFieldInitializerProjection {
			for (module in candidate.getModules())
				for (owner in module.projection.getClasses())
					for (initializer in owner.getFieldInitializers())
						if (initializer.getField().getName() == name)
							return initializer;
			throw "initializer ownership fixture lost its child field";
		}
		function rejected(action:Void->Void, message:String):Void {
			try {
				action();
			} catch (failure:haxe.Exception) {
				if (failure.message.indexOf(message) >= 0)
					return;
				throw failure;
			}
			throw "initializer accepted foreign or mutated ownership";
		}
		final initializer = selected(program);
		storage.initializerMember(storage.initializerApplication(initializer, TyType.nominal(initializer.getField().getOwner(), [])));
		var rejectedEntry = false;
		for (module in program.getModules())
			for (owner in module.projection.getClasses())
				for (fn in owner.getFunctions())
					if (fn.requireSemanticDeclaration().getSignature().getName() == "main") {
						rejected(() -> {
							render({
								projection: fn,
								rootSymbol: "entry",
								symbolPrefix: "hxhx_function_entry",
								classes: storage
							},
								storage.initializerApplication(initializer, TyType.nominal(initializer.getField()
									.getOwner(), [])), "receiver", "initializer_");
						}, "constructor body");
						rejectedEntry = true;
					}
		if (!rejectedEntry)
			throw "initializer ownership fixture missed its non-constructor entry";
		final source = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final other = TyperStage.typeResolvedModule(source, TyperIndex.build([source]));
		final foreignProgram = new CppTypedProgramProjection(new MacroExpandedProgram([other], false));
		final foreign = selected(foreignProgram);
		final localOwner = selected(program, "z");
		final localAccess = new CppManagedExpressionLocals(FieldInitializer(localOwner), "hxhx_value_local_contract_");
		function digit(owner:TypedBackendFieldInitializerProjection):TyLocalBinding {
			for (entry in owner.getLocalCatalog().getEntries())
				if (entry.getBinding().getSourceName() == "digit")
					return entry.getBinding();
			throw "initializer ownership fixture lost its authored local";
		}
		final local = digit(localOwner);
		localAccess.place(local);
		rejected(() -> {
			localAccess.place(digit(selected(foreignProgram, "z")));
		}, "exact root declaration");
		var mutationChecked = false;
		TypedBackendSourceWalk.expression(localOwner.getExpression(), expression -> {
			switch expression {
				case ECall(_, arguments) if (arguments.length > 0 && arguments[arguments.length - 1].match(EInt(9))):
					final slot = arguments.length - 1;
					final saved = arguments[slot];
					arguments[slot] = EInt(8);
					rejected(() -> {
						localAccess.place(local);
					}, "mutated");
					arguments[slot] = saved;
					mutationChecked = true;
				case _:
			}
		});
		if (!mutationChecked)
			throw "initializer ownership fixture missed its nested mutation";
		localAccess.place(local);
		rejected(() -> {
			storage.initializerMember(storage.initializerApplication(foreign, TyType.nominal(foreign.getField().getOwner(), [])));
		}, "initializer");
		final finalOperand = switch initializer.getExpression() {
			case ELoweredControl(Initializer(true), _, entries, _) if (entries.length > 0): entries[entries.length - 1];
			case value: value;
		};
		switch finalOperand {
			case ECall(_, arguments) if (arguments.length > 0):
				final saved = arguments[0];
				arguments[0] = EInt(99);
				rejected(() -> {
					storage.initializerMember(storage.initializerApplication(initializer, TyType.nominal(initializer.getField().getOwner(), [])));
				}, "mutated");
				arguments[0] = saved;
			case _:
				throw "initializer ownership fixture lost its authored call";
		}
		storage.initializerMember(storage.initializerApplication(initializer, TyType.nominal(initializer.getField().getOwner(), [])));
		Sys.println("CPP_INSTANCE_INITIALIZER:OWNERSHIP:PASS");
	}
}
