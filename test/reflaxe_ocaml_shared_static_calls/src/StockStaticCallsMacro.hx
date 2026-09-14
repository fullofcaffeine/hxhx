import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.helpers.ClassFieldHelper;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.target.HaxeOcamlTargetFunctionAdapter;
import reflaxe.ocaml.target.OcamlTargetFunctionLowerer;

/** Independently copy stock-Haxe declarations before any target preprocessing. **/
class StockStaticCallsMacro {
	public static macro function expected():Expr {
		final owner = switch (Context.getType("Main")) {
			case TInst(reference, _): reference.get();
			case _: throw "fixture must resolve Main as a class";
		};
		final results = new Array<Expr>();
		for (field in owner.statics.get()) {
			final data = ClassFieldHelper.findFuncData(field, owner, true);
			final fact = data == null ? null : HaxeOcamlTargetFunctionAdapter.fromSourceBeforePreprocessing(data);
			if (fact == null)
				throw "stock adapter rejected " + field.name;
			final identity = fact.getCanonicalIdentity();
			final syntax = new OcamlASTPrinter().printExpr(OcamlTargetFunctionLowerer.build(fact));
			results.push(macro {name: $v{field.name}, identity: $v{identity}, syntax: $v{syntax}});
		}
		return macro $a{results};
	}
}
