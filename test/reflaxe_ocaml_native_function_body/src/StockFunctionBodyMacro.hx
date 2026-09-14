import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.helpers.ClassFieldHelper;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.target.HaxeOcamlTargetFunctionAdapter;
import reflaxe.ocaml.target.OcamlTargetFunctionLowerer;

/** Captures the same authored function through upstream Haxe before preprocessing. **/
class StockFunctionBodyMacro {
	public static macro function expected():Expr {
		final owner = switch (Context.getType("Main")) {
			case TInst(reference, _): reference.get();
			case _: throw "stock fixture did not resolve Main as a class";
		};
		for (field in owner.statics.get()) {
			if (field.name != "main")
				continue;
			final data = ClassFieldHelper.findFuncData(field, owner, true);
			final fact = data == null ? null : HaxeOcamlTargetFunctionAdapter.fromSourceBeforePreprocessing(data);
			if (fact == null)
				throw "stock adapter rejected the authored function body";
			final identity = fact.getCanonicalIdentity();
			final ocaml = new OcamlASTPrinter().printExpr(OcamlTargetFunctionLowerer.build(fact));
			return macro {identity: $v{identity}, ocaml: $v{ocaml}};
		}
		throw "stock fixture has no main function";
	}
}
