import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type.TVar;
import reflaxe.ocaml.target.HaxeOcamlTargetBindingAdapter;
import reflaxe.ocaml.target.OcamlTargetBindingFact.OcamlTargetBindingRole;

/** Produces a preprocessor-free stock-Haxe binding fact for native comparison. **/
class BindingIdentityMacro {
	public static macro function stockVariable():Expr {
		final typed = Context.typeExpr(macro {
			var value:Int = 1;
			value;
		});
		final local = firstVariable(typed);
		final fact = HaxeOcamlTargetBindingAdapter.fromSourceLocalBeforePreprocessing("unit.BindingFixture.run", "root/block-item/0/binding",
			OcamlTargetBindingRole.Variable, local);
		return macro $v{fact.getCanonicalIdentity()};
	}

	static function firstVariable(expression:haxe.macro.Type.TypedExpr):TVar {
		return switch (expression.expr) {
			case TBlock(expressions) if (expressions.length > 0):
				switch (expressions[0].expr) {
					case TVar(local, _): local;
					case _: throw "stock Haxe binding fixture did not type its first expression as a variable declaration";
				}
			case _: throw "stock Haxe binding fixture did not type as a block";
		};
	}
}
