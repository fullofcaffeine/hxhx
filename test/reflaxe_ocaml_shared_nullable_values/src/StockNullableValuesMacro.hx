import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.helpers.ClassFieldHelper;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.target.HaxeOcamlTargetFunctionAdapter;
import reflaxe.ocaml.target.OcamlTargetFunctionLowerer;

/** Compare original stock-Haxe functions before any target preprocessing occurs. */
class StockNullableValuesMacro {
	public static macro function expected():Expr {
		final owner = switch (Context.getType("Main")) {
			case TInst(reference, _): reference.get();
			case _: throw "nullable fixture requires Main";
		};
		final rows = new Array<Expr>();
		for (field in owner.statics.get()) {
			final data = ClassFieldHelper.findFuncData(field, owner, true);
			final fact = data == null ? null : HaxeOcamlTargetFunctionAdapter.fromSourceBeforePreprocessing(data);
			final admitted = fact != null;
			final identity = fact == null ? "" : fact.getCanonicalIdentity();
			final syntax = fact == null ? "" : new OcamlASTPrinter().printExpr(OcamlTargetFunctionLowerer.build(fact));
			rows.push(macro {
				name: $v{field.name},
				admitted: $v{admitted},
				identity: $v{identity},
				syntax: $v{syntax}
			});
		}
		return macro $a{rows};
	}
}
