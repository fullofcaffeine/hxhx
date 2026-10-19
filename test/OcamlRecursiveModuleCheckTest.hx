import reflaxe.ocaml.ast.OcamlRecursiveModuleCheck;
import reflaxe.ocaml.ast.OcamlRecursiveModuleCheck.checkRecursiveModule;
import reflaxe.ocaml.ast.OcamlLetBinding;
import reflaxe.ocaml.ast.OcamlModuleItem;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlRawInjection;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;

/** An exported function type must never hide eager recursive-module initialization. */
class OcamlRecursiveModuleCheckTest {
	public static function run():Void {
		checkNullCells();
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

	/** A checked null reference is still an unsafe module member, never a recursion anchor. */
	static function checkNullCells():Void {
		final binding = nullCell("cache", TIdent("Obj.t"));
		switch (checkRecursiveModule([ILet([binding], false)])) {
			case RecursiveModuleReady([SValue("cache", TApp("ref", [TIdent("Obj.t")]))], false):
			case _:
				throw "checked null cell lost its exact type or became a safe recursion anchor";
		}
		reject({name: "missing_cell_type", expr: binding.expr}, EagerInitializer("missing_cell_type"));
		reject({name: "wrong_cell_type", expr: binding.expr, signature: TApp("ref", [TIdent("string")])}, EagerInitializer("wrong_cell_type"));
		reject({
			name: "hidden_cell",
			expr: binding.expr,
			signature: binding.signature,
			visibility: CompilerInternal
		}, UnsupportedInternalBinding("hidden_cell"));
		for (initializer in [
			EIdent("HxRuntime.hx_null"),
			EField(EIdent("HxRuntime"), "hx_null"),
			OcamlASTTraversalTest.runtimeIdentifierExpression(),
			EApp(EIdent("Factory.make"), [EConst(CUnit)]),
			EConst(CInt(0))
		]) {
			reject({name: "unproved_cell", expr: EApp(EIdent("ref"), [EAnnot(initializer, TIdent("Obj.t"))]), signature: binding.signature},
				EagerInitializer("unproved_cell"));
		}
	}

	/** Uses the real runtime authority so a printed null name cannot stand in for checked storage. */
	public static function nullCell(name:String, carrier:OcamlTypeExpr):OcamlLetBinding {
		final requirement = OcamlRuntimeRequirementLedger.requirementForCompilerInfrastructure(OcamlRuntimeRequirementLedger.CORE_RUNTIME);
		final authority = new OcamlRuntimeUseAuthority("null-cell-test", "portable", [requirement], [
			{
				id: "null-cell-use",
				planRevision: "null-cell-test",
				ownerId: "null-cell",
				requirementId: requirement.id,
				domain: ExpressionIdentifier,
				exactSymbol: "HxRuntime.hx_null",
				role: "null-cell-default",
				order: 0,
				source: {
					file: "NullCell.hx",
					min: 0,
					max: 1
				},
				profileEligibility: ["portable"],
				cardinality: 1
			}
		]);
		final value = ERuntimeIdent(authority.expressionIdentifier("null-cell-use", "null-cell-test", "HxRuntime.hx_null"));
		return {name: name, expr: EApp(EIdent("ref"), [EAnnot(EApp(EIdent("Obj.magic"), [value]), carrier)]), signature: TApp("ref", [carrier])};
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
