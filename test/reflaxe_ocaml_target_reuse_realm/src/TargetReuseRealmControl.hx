#if macro
import haxe.macro.Expr;
import reflaxe.lifecycle.TargetReuseCatalog;
#end

/** Test-only command macros for explicit catalog reset. **/
class TargetReuseRealmControl {
	#if macro
	public static macro function reset(cause:String):Expr {
		TargetReuseCatalog.resetShared(cause);
		return macro null;
	}
	#end
}
