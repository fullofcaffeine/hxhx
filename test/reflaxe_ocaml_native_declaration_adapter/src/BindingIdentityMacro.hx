import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type.TypedExpr;
import haxe.macro.Type.TVar;
import reflaxe.ocaml.target.HaxeOcamlTargetBindingAdapter;
import reflaxe.ocaml.target.HaxeOcamlTargetExpressionAdapter;
import reflaxe.ocaml.target.OcamlTargetBindingFact.OcamlTargetBindingRole;

/** Produces a preprocessor-free stock-Haxe binding fact for native comparison. **/
class BindingIdentityMacro {
	public static macro function stockVariable():Expr {
		final typed = typedFixture();
		final local = firstVariable(typed);
		final fact = HaxeOcamlTargetBindingAdapter.fromSourceLocalBeforePreprocessing("unit.BindingFixture.run", "root/block-item/0/binding",
			OcamlTargetBindingRole.Variable, local);
		return macro $v{fact.getCanonicalIdentity()};
	}

	public static macro function stockExpression():Expr {
		final fact = HaxeOcamlTargetExpressionAdapter.fromSourceBeforePreprocessing("unit.BindingFixture.run", typedFixture());
		if (fact == null)
			Context.error("stock Haxe adapter rejected the recursive expression fixture", Context.currentPos());
		return macro $v{fact.getCanonicalIdentity()};
	}

	public static macro function stockUnsupportedExpression():Expr {
		final fact = HaxeOcamlTargetExpressionAdapter.fromSourceBeforePreprocessing("unit.BindingFixture.unsupported", Context.typeExpr(macro {
			var value:Float = 7;
			value;
		}));
		return macro $v{fact == null};
	}

	static function typedFixture():TypedExpr
		return Context.typeExpr(macro {
			var value:Int = 7;
			value;
		});

	static function firstVariable(expression:TypedExpr):TVar {
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
