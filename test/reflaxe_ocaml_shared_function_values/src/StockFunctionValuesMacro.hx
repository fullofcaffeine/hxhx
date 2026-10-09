import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.helpers.ClassFieldHelper;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.target.HaxeOcamlTargetFunctionAdapter;
import reflaxe.ocaml.target.OcamlTargetFunctionLowerer;

/** Observe stock-Haxe admission separately so the runtime test can report both host boundaries. */
class StockFunctionValuesMacro {
	public static macro function expected():Expr {
		final owner = switch (Context.getType("Main")) {
			case TInst(reference, _): reference.get();
			case _: throw "shared function values require the authored Main class";
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
