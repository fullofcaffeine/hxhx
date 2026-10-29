import backend.cpp.CppTargetCore;
import backend.cpp.CppTypedProgramProjection;

/** Return classification must use the callee's bindings and raw projected names. */
class M14CppErasedReturnOwnershipTest {
	public static function run():Void {
		final source = 'class Main {
 static function target(value:Int):Dynamic return value;
 static function caller(value:Dynamic):Dynamic return target(1);
 static function arrayValue():Dynamic { var int = [1]; return int; }
 static function recursive(value:Int):Dynamic { if (value > 0) return recursive(value - 1); return value; }
}';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final owner = program.getModules()[0].projection.getClasses()[0];
		final lookup = @:privateAccess CppTargetCore.collectClassLookup(program);
		final scope = @:privateAccess CppTargetCore.renderScope(owner.getDeclaration(), lookup, "std::any");
		@:privateAccess CppTargetCore.registerFunctionArgs(scope, owner.getFunctions()[1].getDeclaration());
		scope.localTypes.set("value", "std::any");
		if (@:privateAccess CppTargetCore.sameOwnerCallReturnsErasedDynamicValue("target", scope))
			throw "Callee integer return borrowed the caller's erased parameter";
		if (!(@:privateAccess CppTargetCore.sameOwnerCallReturnsErasedDynamicValue("arrayValue", scope)))
			throw "Callee array return lost its own local representation";
		if (@:privateAccess CppTargetCore.sameOwnerCallReturnsErasedDynamicValue("recursive", scope))
			throw "Recursive integer return borrowed caller-local facts";
		scope.localTypes.set("value", "int");
		if (@:privateAccess CppTargetCore.sameOwnerCallReturnsErasedDynamicValue("target", scope))
			throw "Warm return classification changed with caller-local facts";
		final locals = new haxe.ds.StringMap<Bool>();
		final declaration = HxStmt.SVar("int", "", HxExpr.EArrayDecl([HxExpr.EInt(1)]), HxPos.unknown());
		@:privateAccess CppTargetCore.stmtReturnsErasedDynamicValue(declaration, scope, locals);
		if (!locals.exists("int") || locals.exists("int_"))
			throw "Erased local inventory used an escaped output name";
		final lambda = HxExpr.ECall(HxExpr.ELambda(["int"], HxExpr.EIdent("int")), [HxExpr.EArrayDecl([HxExpr.EInt(1)])]);
		if (!(@:privateAccess CppTargetCore.exprReturnsErasedDynamicValue(lambda, scope, new haxe.ds.StringMap<Bool>())))
			throw "Erased lambda parameter lost its raw binding name";
		Sys.println("CPP_ERASED_RETURN_OWNERSHIP:PASS");
	}

	static function main():Void
		run();
}
