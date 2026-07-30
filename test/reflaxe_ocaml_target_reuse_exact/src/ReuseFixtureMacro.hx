#if macro
import haxe.io.Bytes;
import haxe.macro.Context;

/** Supplies one generated resource whose revision must participate in reuse. **/
class ReuseFixtureMacro {
	/** Installs the deterministic resource consumed by the runtime fixture. **/
	public static function install():Void {
		Context.addResource("reuse-payload", Bytes.ofString("resource-a"));
	}
}
#end
