import reflaxe.ocaml.ast.OcamlFunctionModuleCheck;
import reflaxe.ocaml.ast.OcamlFunctionModuleCheck.checkFunctionModule;
import reflaxe.ocaml.ast.OcamlLetBinding;
import reflaxe.ocaml.ast.OcamlModuleItem;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlRawInjection;
import reflaxe.ocaml.ast.OcamlTypeExpr;

/** An exported function type must never hide eager recursive-module initialization. */
class OcamlFunctionModuleCheckTest {
	public static function run():Void {
		final callable = TArrow(TIdent("unit"), TIdent("int"));
		final delayed = EFun([PConst(CUnit)], EApp(EIdent("Other.run"), [EConst(CUnit)]));
		final accepted = checkFunctionModule([
			IType([{name: "t", params: [], kind: Alias(TIdent("int"))}], false),
			ILet([
				{name: "arbitrary_internal_name", expr: EConst(CUnit), visibility: CompilerInternal},
				{name: "run", expr: EAnnot(delayed, callable), signature: callable}
			], false)
		]);
		switch (accepted) {
			case FunctionModuleReady([SType(_, false), SValue("run", _)]):
			case _:
				throw "function declarations or internal marker were misclassified";
		}
		reject({name: "run", expr: EApp(EIdent("Factory.make"), [EConst(CUnit)]), signature: callable}, EagerInitializer("run"));
		reject({name: "hidden", expr: EApp(EIdent("Other.run"), [EConst(CUnit)]), visibility: CompilerInternal}, UnsupportedInternalBinding("hidden"));
		reject({name: "visible_unit", expr: EConst(CUnit)}, EagerInitializer("visible_unit"));
		reject({name: "missing", expr: delayed}, MissingSignature("missing"));
		reject({name: "wrong", expr: delayed, signature: TIdent("int")}, InvalidFunctionSignature("wrong"));
		reject({name: "arity", expr: EFun([PConst(CUnit), PConst(CUnit)], EConst(CInt(1))), signature: callable}, InvalidFunctionSignature("arity"));
		reject({name: "empty", expr: EFun([], EConst(CInt(1))), signature: callable}, EagerInitializer("empty"));
		reject({name: "hidden_function", expr: delayed, visibility: CompilerInternal}, UnsupportedInternalBinding("hidden_function"));
		final injection = switch (OcamlRawInjection.plan("Other.run ()", 0)) {
			case PlanReady(plan): switch (OcamlRawInjection.materialize(plan, new Array<OcamlExpr>())) {
					case InjectionReady(value): value;
					case InjectionInvalid(message): throw message;
				}
			case PlanInvalid(message): throw message;
		};
		reject({name: "opaque", expr: EFun([PConst(CUnit)], ERawInjection(injection)), signature: callable}, OpaqueModule);
	}

	static function reject(binding:OcamlLetBinding, expected:OcamlFunctionModuleProblem):Void {
		switch (checkFunctionModule([ILet([binding], false)])) {
			case FunctionModuleRejected(actual):
				if (!Type.enumEq(actual, expected))
					throw "wrong rejection: " + Std.string(actual) + " expected " + Std.string(expected);
			case FunctionModuleReady(_):
				throw "unsafe or incomplete function module was accepted";
		}
	}
}
