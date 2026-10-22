import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Native behavior must preserve each source binding despite target name collisions. */
class M14CppStrictLocalBindingIntegrationTest {
	/** The generated-source smoke also runs this mandatory native check. */
	public static function run():Void {
		assertAnalysisKeepsSourceNames();
		assertDirectConsumersKeepSymbols();
		final root = "test/oracle/cpp_strict_local_binding_seed";
		final path = root + "/src/Main.hx";
		final typed = TyperStage.typeModule(ParserStage.parse(sys.io.File.getContent(path), path));
		final program = new MacroExpandedProgram([typed], false);
		final directory = ".tmp/cpp-strict-local-bindings";
		final context = new BackendContext(directory, null, "Main", true, true, new haxe.ds.StringMap<String>());
		final result = CppTargetCore.emit(program, context);
		if (!result.builtExecutable)
			throw "C++ local binding test requires a native executable";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent(root + "/expected.stdout"))
			throw "C++ local binding behavior differs: " + stdout + stderr;
		Sys.println("CPP_STRICT_LOCAL_BINDING_NATIVE:PASS");
	}

	/** Analysis must distinguish a keyword-shaped source name from its valid C++ neighbor. */
	static function assertAnalysisKeepsSourceNames():Void {
		final callsKeyword = [HxStmt.SExpr(HxExpr.ECall(HxExpr.EIdent("int"), []), HxPos.unknown())];
		if (@:privateAccess CppTargetCore.functionArgMayNeedCallableArgTypeOverride("String", "int_", callsKeyword))
			throw "Calling int must not make the distinct int_ parameter callable";
		if (!(@:privateAccess CppTargetCore.functionArgMayNeedCallableArgTypeOverride("String", "int", callsKeyword)))
			throw "Calling int must retain callable inference for that exact parameter";
		final candidates = new haxe.ds.StringMap<Bool>();
		candidates.set("int", true);
		candidates.set("int_", true);
		final args = [
			new HxFunctionArg("int", "Dynamic", NoDefault, false, false),
			new HxFunctionArg("int_", "Dynamic", NoDefault, false, false)
		];
		final usage = [
			HxStmt.SExpr(HxExpr.EBinop("==", HxExpr.EIdent("int"), HxExpr.EInt(1)), HxPos.unknown())
		];
		final api = @:privateAccess CppTargetCore.localTypeInferenceApi();
		final used = backend.cpp.CppLocalTypeInference.erasedDynamicArgUsageNames(args, usage, candidates, api);
		if (!used.exists("int") || used.exists("int_"))
			throw "Erased-value inference must retain the exact source argument name";
		final owner = new HxClassDecl("InferenceOwner", false, [], []);
		final lookup = {names: new haxe.ds.StringMap<Bool>(), byName: new haxe.ds.StringMap<HxClassDecl>()};
		final scope = @:privateAccess CppTargetCore.renderScope(owner, lookup, "void");
		final statements = [
			HxStmt.SVar("int", "", HxExpr.ENew("haxe.ds.StringMap", []), HxPos.unknown()),
			HxStmt.SVar("int_", "", HxExpr.ENew("haxe.ds.StringMap", []), HxPos.unknown()),
			HxStmt.SExpr(HxExpr.ECall(HxExpr.EField(HxExpr.EIdent("int"), "set"), [HxExpr.EString("key"), HxExpr.EInt(1)]), HxPos.unknown()),
			HxStmt.SExpr(HxExpr.ECall(HxExpr.EField(HxExpr.EIdent("int_"), "set"), [HxExpr.EString("key"), HxExpr.EString("value")]), HxPos.unknown())
		];
		backend.cpp.CppLocalTypeInference.inferStringMapLocalTypeOverridesFromStmts(scope, statements, api);
		if (scope.localTypeOverrides.get("int") != "std::shared_ptr<StringMap<int>>"
			|| scope.localTypeOverrides.get("int_") != "std::shared_ptr<StringMap<std::string>>")
			throw "Map inference must keep the value representation of each source binding";
		if (scope.localNames.iterator().hasNext() || scope.localNameCounts.iterator().hasNext())
			throw "Map inference must not allocate output symbols";
		scope.localTypes.set("int", "std::function<int()>");
		scope.localTypes.set("int_", "std::function<std::string()>");
		if ((@:privateAccess CppTargetCore.callableOrSameOwnerReturnCppType("int", scope)) != "int")
			throw "Callable return inference borrowed an escaped neighbor";
		if ((@:privateAccess CppTargetCore.lambdaCallReturnCppType(["int"], HxExpr.EIdent("int"), [HxExpr.EInt(3)], scope)) != "int")
			throw "Immediate lambda inference installed its parameter under an output spelling";
		scope.localTypes.set("int", "int");
		scope.localTypes.set("int_", "std::any");
		if (@:privateAccess CppTargetCore.exprReturnsErasedDynamicValue(HxExpr.EIdent("int"), scope))
			throw "Integer return classification borrowed a neighboring erased value";
		final falseIdentity = new HxFunctionDecl("falseIdentity", Public, true, [args[0]], "Dynamic",
			[HxStmt.SReturn(HxExpr.EIdent("int_"), HxPos.unknown())], "");
		if (@:privateAccess CppTargetCore.isDynamicIdentityFunction(falseIdentity))
			throw "Returning a neighboring field must not classify as returning the parameter";
	}

	/** Direct storage and callback renderers must use the same selected binding as ordinary reads. */
	static function assertDirectConsumersKeepSymbols():Void {
		final source = 'class Main {
 static function choose(?int:Int):Int { var int_ = 9; return int == null ? int_ : int; }
 static function callback(int:EReg):String { var int_:EReg = int; return int.matchedLeft(); }
 static function main():Void {}
}
extern class EReg { public function matchedLeft():String; }';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new backend.cpp.CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final owner = program.getModules()[0].projection.getClasses()[0];
		final lookup = @:privateAccess CppTargetCore.collectClassLookup(program);
		final optionalScope = @:privateAccess CppTargetCore.renderScope(owner.getDeclaration(), lookup, "int");
		@:privateAccess CppTargetCore.prepareFunctionScope(optionalScope, owner.getFunctions()[0].getDeclaration());
		final optionalSymbol = optionalScope.executableLocals.symbol("int");
		if (optionalSymbol == "int_"
			|| (@:privateAccess CppTargetCore.optionalStorageExpr(HxExpr.EIdent("int"), optionalScope)) != optionalSymbol)
			throw "Optional storage must use its exact parameter symbol";
		final callbackScope = @:privateAccess CppTargetCore.renderScope(owner.getDeclaration(), lookup, "std::string");
		@:privateAccess CppTargetCore.prepareFunctionScope(callbackScope, owner.getFunctions()[1].getDeclaration());
		final callbackSymbol = callbackScope.executableLocals.symbol("int");
		final body = HxExpr.ECall(HxExpr.EField(HxExpr.EIdent("int"), "matchedLeft"), []);
		final rendered = @:privateAccess CppTargetCore.directIsolatedERegStringCallbackBodyExpr(body, ["int"], ["std::shared_ptr<EReg>"], "std::string",
			callbackScope);
		if (rendered != callbackSymbol + "->matchedLeft()")
			throw "Direct callback rendering must use its exact parameter symbol";
		final captured = HxExpr.ECall(HxExpr.EField(HxExpr.EIdent("int_"), "matchedLeft"), []);
		if ((@:privateAccess CppTargetCore.directIsolatedERegStringCallbackBodyExpr(captured, ["int"], ["std::shared_ptr<EReg>"], "std::string",
			callbackScope)) != null)
			throw "The isolated callback path must decline a different captured binding";
	}

	static function main():Void
		run();
}
