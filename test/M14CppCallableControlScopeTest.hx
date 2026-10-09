import backend.cpp.CppRenderScope;
import backend.cpp.CppTargetCore;

/** Callback inference must follow lexical scopes and the innermost function result contract. */
@:access(backend.cpp.CppTargetCore)
class M14CppCallableControlScopeTest {
	static function scope():CppRenderScope {
		final owner = new HxClassDecl("CallbackScope", false, [], []);
		return CppTargetCore.renderScope(owner, {names: new haxe.ds.StringMap<Bool>(), byName: new haxe.ds.StringMap<HxClassDecl>()}, "void");
	}

	static function call():HxExpr
		return ECall(EIdent("callback"), [EInt(7)]);

	static function region(kind:HxLoweredControlKind, children:Array<HxExpr>):HxExpr
		return ELoweredControl(kind, "function", children, HxPos.unknown());

	static function returned(value:HxExpr):HxExpr
		return region(Return, [value]);

	static function declaration(name:String, hint:String, value:HxExpr):HxExpr
		return EVars([EVariableDeclaration(name, hint, value, HxPos.unknown(), false, false)]);

	static function analyze(expression:HxExpr, expectedType:String, ?current:CppRenderScope):CppRenderScope {
		if (current == null)
			current = scope();
		final candidates = new haxe.ds.StringMap<Bool>();
		candidates.set("callback", true);
		CppTargetCore.collectCallableArgTypeOverridesFromExpr(expression, current, candidates, expectedType);
		if (!candidates.exists("callback"))
			throw "Child analysis modified its caller's candidate set";
		return current;
	}

	static function expect(current:CppRenderScope, type:String):Void {
		if (current.argTypeOverrides.get("callback") != type)
			throw "Wrong callback contract: expected " + type + ", got " + current.argTypeOverrides.get("callback");
		if (current.localTypes.exists("argument") || current.localTypes.exists("result"))
			throw "Nested callback analysis leaked declaration facts";
	}

	public static function run():Void {
		final integerResult = new HxLambdaSignature([], "Int");
		final stringResult = new HxLambdaSignature([], "String");
		expect(analyze(ELambda([], region(FunctionBody, [returned(call())]), integerResult), ""), "std::function<int(int)>");
		expect(analyze(ELambda([], region(FunctionBody, [returned(call())])), "std::function<int()>"), "std::function<int(int)>");
		// The nested result belongs to its own function, not the outer Int-returning function.
		final nested:HxExpr = ELambda([], region(FunctionBody, [returned(call())]), stringResult);
		expect(analyze(ELambda([], region(FunctionBody, [nested, returned(EInt(0))]), integerResult), ""), "std::function<std::string(int)>");
		// An earlier declaration without candidate references still supplies the call operand type.
		final body = region(FunctionBody, [
			declaration("argument", "Int", EInt(7)),
			declaration("result", "Int", ECall(EIdent("callback"), [EIdent("argument")])),
			returned(EIdent("result"))
		]);
		expect(analyze(ELambda([], body, integerResult), ""), "std::function<int(int)>");
		// A declaration initializer sees the outer binding; the declared name hides it afterward.
		final shadowBody = region(FunctionBody, [declaration("callback", "Int", call()), returned(EIdent("callback"))]);
		expect(analyze(ELambda([], shadowBody, integerResult), ""), "std::function<int(int)>");
		final parameterShadow:HxExpr = ELambda(["callback"], region(FunctionBody, [returned(call())]), new HxLambdaSignature([
			{
				typeHint: "Int->Int",
				isOptional: false,
				isRest: false,
				hasDefault: false
			}
		], "Int"));
		final original = scope();
		original.argTypeOverrides.set("callback", "outer contract");
		original.localTypes.set("callback", "outer type");
		expect(analyze(parameterShadow, "", original), "outer contract");
		if (original.localTypes.get("callback") != "outer type")
			throw "Lambda parameter leaked its local type";
		// A branch-local shadow must neither erase prior evidence nor hide the next outer use.
		final branch = region(Branch, [EBool(true), region(Scope, [declaration("callback", "Int", EInt(2))])]);
		expect(analyze(ELambda([], region(FunctionBody, [branch, returned(call())]), integerResult), ""), "std::function<int(int)>");
		for (loop in [
			region(While(Normal), [EBool(true), region(Scope, [returned(call())])]),
			region(While(DoWhile), [EBool(false), region(Scope, [returned(call())])]),
			region(For(Value("argument")), [
				ERange(EInt(0), EInt(2)),
				region(Scope, [returned(ECall(EIdent("callback"), [EIdent("argument")]))])
			])
		])
			expect(analyze(ELambda([], region(FunctionBody, [loop]), integerResult), ""), "std::function<int(int)>");
		final switchBody = region(Switch([PBind("callback"), PWildcard]), [
			EInt(2),
			region(Scope, [returned(EIdent("callback"))]),
			region(Scope, [returned(call())])
		]);
		expect(analyze(ELambda([], region(FunctionBody, [switchBody]), integerResult), ""), "std::function<int(int)>");
		Sys.println("CPP_CALLABLE_CONTROL_SCOPE:PASS");
	}

	static function main():Void
		run();
}
