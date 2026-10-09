import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.target.HaxeOcamlTargetFieldInitializerAdapter;

/** Captures the shared source fixture's initializer through upstream Haxe. **/
class StockFieldInitializerMacro {
	public static macro function expectedIdentity():Expr {
		final owner = switch (Context.getType("Main")) {
			case TInst(reference, _): reference.get();
			case _: throw "stock initializer fixture did not resolve Main as a class";
		};
		for (field in owner.statics.get()) {
			if (field.name != "value")
				continue;
			final expression = field.expr();
			final fact = expression == null ? null : HaxeOcamlTargetFieldInitializerAdapter.fromSourceBeforePreprocessing(owner, field, expression);
			if (fact == null)
				throw "stock adapter rejected the authored field initializer";
			return macro $v{fact.getCanonicalIdentity()};
		}
		throw "stock initializer fixture has no value field";
	}
}
