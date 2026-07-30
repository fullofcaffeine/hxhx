#if macro
import haxe.macro.Expr;
import reflaxe.lifecycle.TargetReuseCatalog;
#end

/** Test-only command macros for the exact source-reuse catalog. **/
class ReuseTargetCatalogControl {
	#if macro
	/** Clears the current macro realm's catalog before target lookup. **/
	public static macro function reset(cause:String):Expr {
		TargetReuseCatalog.resetShared(cause);
		return macro null;
	}
	#end
}
