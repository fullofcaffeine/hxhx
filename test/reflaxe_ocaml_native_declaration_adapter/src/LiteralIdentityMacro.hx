import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type.TConstant;
import reflaxe.ocaml.target.HaxeOcamlTargetLiteralAdapter;

/** Produces stock-Haxe literal evidence for the runtime native-adapter fixture. **/
class LiteralIdentityMacro {
	public static macro function stockInt():Expr {
		final fact = HaxeOcamlTargetLiteralAdapter.fromConstant(TInt(7), Context.typeof(macro 7));
		if (fact == null)
			Context.error("stock Haxe adapter rejected an integer literal", Context.currentPos());
		return macro $v{fact.getCanonicalIdentity()};
	}
}
