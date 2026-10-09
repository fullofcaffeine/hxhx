import reflaxe.ocaml.ast.OcamlRecursiveModuleCheck;
import reflaxe.ocaml.ast.OcamlRecursiveModuleCheck.checkRecursiveModule;
import reflaxe.ocaml.ast.OcamlLetBinding;
import reflaxe.ocaml.ast.OcamlModuleItem;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlRawInjection;
import reflaxe.ocaml.ast.OcamlTypeExpr;

/** An exported function type must never hide eager recursive-module initialization. */
class OcamlRecursiveModuleCheckTest {
	public static function run():Void {
		final callable = TArrow(TIdent("unit"), TIdent("int"));
		final delayed = EFun([PConst(CUnit)], EApp(EIdent("Other.run"), [EConst(CUnit)]));
		final accepted = checkRecursiveModule([
			IType([{name: "t", params: [], kind: Alias(TIdent("int"))}], false),
			ILet([
				{name: "arbitrary_internal_name", expr: EConst(CUnit), visibility: CompilerInternal},
				{name: "run", expr: EAnnot(delayed, callable), signature: callable}
			], false)
		]);
		switch (accepted) {
			case RecursiveModuleReady([SType(_, false), SValue("run", _)], true):
			case _:
				throw "function declarations or internal marker were misclassified";
		}
		for (entry in [
			{expr: EConst(CInt(7)), type: "int"},
			{expr: EConst(CBool(true)), type: "bool"},
			{expr: EAnnot(EConst(CString("ready")), TIdent("string")), type: "string"}
		]) {
			switch (checkRecursiveModule([ILet([{name: "literal", expr: entry.expr}], false)])) {
				case RecursiveModuleReady([SValue("literal", TIdent(name))], false) if (name == entry.type):
				case _:
					throw "literal did not retain its type or was marked function-only";
			}
		}
		reject({name: "pretend_function", expr: EConst(CInt(1)), signature: callable}, InvalidLiteralSignature("pretend_function"));
		reject({name: "wrong_literal", expr: EConst(CBool(true)), signature: TIdent("int")}, InvalidLiteralSignature("wrong_literal"));
		reject({name: "wrong_annotation", expr: EAnnot(EConst(CString("ready")), TIdent("Obj.t"))}, EagerInitializer("wrong_annotation"));
		reject({name: "allocation", expr: EApp(EIdent("ref"), [EConst(CInt(0))])}, EagerInitializer("allocation"));
		reject({name: "hidden_literal", expr: EConst(CInt(0)), visibility: CompilerInternal}, UnsupportedInternalBinding("hidden_literal"));
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

	static function reject(binding:OcamlLetBinding, expected:OcamlRecursiveModuleProblem):Void {
		switch (checkRecursiveModule([ILet([binding], false)])) {
			case RecursiveModuleRejected(actual):
				if (!Type.enumEq(actual, expected))
					throw "wrong rejection: " + Std.string(actual) + " expected " + Std.string(expected);
			case RecursiveModuleReady(_, _):
				throw "unsafe or incomplete function module was accepted";
		}
	}
}
