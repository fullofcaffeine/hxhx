import backend.cpp.CppTargetCore;
import backend.cpp.CppTypedProgramProjection;

/** Call matching must interpret parameters in the callee, even when caller names match. */
class M14CppCalleeArgumentOwnershipTest {
	public static function run():Void {
		final source = 'class Main {
 static function target(?value:Int, enabled:Bool):Int return value == null ? 0 : value;
 static function caller(value:Bool, input:Int):Int return target(input, value);
 static function generic<T>(value:T):T return value;
}';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final owner = program.getModules()[0].projection.getClasses()[0];
		final lookup = @:privateAccess CppTargetCore.collectClassLookup(program);
		final caller = owner.getFunctions()[1].getDeclaration();
		final target = owner.getFunctions()[0].getDeclaration();
		final scope = @:privateAccess CppTargetCore.renderScope(owner.getDeclaration(), lookup, "int");
		@:privateAccess CppTargetCore.prepareFunctionScope(scope, caller);
		// A valid caller inference result must not replace the target's Int parameter.
		scope.argTypeOverrides.set("value", "bool");
		final parameter = HxFunctionDecl.getArgs(target)[0];
		if ((@:privateAccess CppTargetCore.cppFunctionArgType(parameter, scope)) != "std::optional<int>")
			throw "C++ callee parameter borrowed a same-named caller override";
		if (!(@:privateAccess CppTargetCore.callArgMatchesParam(HxExpr.EIdent("input"), parameter, scope)))
			throw "C++ optional argument matching used caller ownership for a callee parameter";
		final candidates = new haxe.ds.StringMap<Bool>();
		candidates.set("input", true);
		@:privateAccess CppTargetCore.collectSameOwnerDeclaredArgTypeOverrides("target", [HxExpr.EIdent("input")], scope, candidates);
		if (scope.localTypeOverrides.get("input") != "int" || scope.argTypeOverrides.get("value") != "bool")
			throw "C++ forwarded inference mixed caller and callee parameter facts";
		scope.typeParams.push("T");
		scope.typeParamCppNames.set("T", "std::string");
		final generic = owner.getFunctions()[2].getDeclaration();
		if ((@:privateAccess CppTargetCore.cppFunctionArgType(HxFunctionDecl.getArgs(generic)[0], scope)) != "T")
			throw "C++ callee generic parameter borrowed the caller type substitution";
		var rejected = false;
		try {
			@:privateAccess CppTargetCore.cppFunctionArgType(new HxFunctionArg("value", "Int", NoDefault, true, false), scope);
		} catch (error:haxe.Exception) {
			if (error.message.indexOf("foreign function parameter") < 0)
				throw error;
			rejected = true;
		}
		if (!rejected)
			throw "C++ accepted a same-shaped parameter from outside the program";
		assertNativeIntAdapter(scope);
		Sys.println("CPP_CALLEE_ARGUMENT_OWNERSHIP:PASS");
	}

	/** A target-only parameter contract must preserve the existing Int adapter behavior. */
	static function assertNativeIntAdapter(scope:backend.cpp.CppRenderScope):Void {
		scope.localTypes.set("input", "std::optional<int>");
		if ((@:privateAccess CppTargetCore.eRegIntCallArgExpr(HxExpr.EIdent("input"), true, scope)) != "input")
			throw "EReg optional Int adaptation lost its storage";
		scope.localTypes.set("input", "std::any");
		if ((@:privateAccess CppTargetCore.eRegIntCallArgExpr(HxExpr.EIdent("input"), false, scope)) != "static_cast<int>(__hxhx_any_double(input))")
			throw "EReg erased Int adaptation changed its conversion";
		if ((@:privateAccess CppTargetCore.eRegIntCallArgExpr(HxExpr.EInt(7), false, scope)) != "7")
			throw "EReg literal Int adaptation changed its value";
	}

	static function main():Void
		run();
}
