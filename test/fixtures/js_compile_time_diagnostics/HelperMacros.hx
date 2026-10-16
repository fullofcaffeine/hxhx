import haxe.macro.Context;
import haxe.macro.Expr;

/** Independent upstream oracle for the existing diagnostic compatibility adapter. */
class HelperMacros {
	public static macro function typeError(expression:Expr):Expr {
		var rejected = false;
		try {
			Context.typeof(expression);
		} catch (error:haxe.macro.Expr.Error) {
			rejected = true;
		}
		return Context.makeExpr(rejected, expression.pos);
	}

	public static macro function typeErrorText(expression:Expr):Expr {
		var message:Null<String> = null;
		try {
			Context.typeof(expression);
		} catch (error:haxe.macro.Expr.Error) {
			message = error.message;
		}
		return Context.makeExpr(message, expression.pos);
	}
}
