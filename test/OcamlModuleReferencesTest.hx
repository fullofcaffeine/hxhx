import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlModuleItem;
import reflaxe.ocaml.ast.OcamlModuleReferences;
import reflaxe.ocaml.ast.OcamlRawInjection;

/** Separates delayed function references, eager initializers, types, and opaque text. */
class OcamlModuleReferencesTest {
	public static function run():Void {
		final summary = OcamlModuleReferences.collect([
			ILet([
				{
					name: "run",
					expr: EAnnot(EFun([PConst(CUnit)], ESeq([
						EIdent("Right.run"),
						EField(EIdent("Left"), "run"),
						EIdent("Right.run"),
						ERecord([{name: "Labels.value", value: EConst(CUnit)}]),
						EField(EIdent("record"), "Fields.value"),
						EConst(CString("NotAModule.run")),
						EField(EIdent("record"), "field")
					])), TArrow(TIdent("unit"), TIdent("Result.t"))),
					signature: TArrow(TIdent("Argument.t"), TIdent("Result.t"))
				}
			],
				false),
			ILet([{name: "initial", expr: EApp(EIdent("Boot.load"), [EConst(CUnit)])}], false),
			IType([{name: "t", params: [], kind: Alias(TApp("Container.t", [TIdent("Element.t")]))}], false)
		]);
		check("Fields,Labels,Left,Right", summary.functionModules.join(","), "function references");
		check("Boot", summary.initializationModules.join(","), "initializer references");
		check("Argument,Container,Element,Result", summary.typeModules.join(","), "type references");
		if (summary.hasOpaqueText)
			throw "ordinary structured declarations became opaque";

		final raw = switch (OcamlRawInjection.plan("Unknown.call {0}", 1)) {
			case PlanReady(plan): switch (OcamlRawInjection.materialize(plan, [OcamlExpr.EIdent("Visible.value")])) {
					case InjectionReady(injection): injection;
					case InjectionInvalid(message): throw message;
				}
			case PlanInvalid(message): throw message;
		};
		final opaque = OcamlModuleReferences.collect([ILet([{name: "raw", expr: ERawInjection(raw)}], false)]);
		check("Visible", opaque.initializationModules.join(","), "typed raw argument");
		if (!opaque.hasOpaqueText)
			throw "raw text was treated as a complete dependency observation";
	}

	static function check(expected:String, actual:String, context:String):Void {
		if (expected != actual)
			throw context + ": expected " + expected + ", got " + actual;
	}
}
