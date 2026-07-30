#if macro
import haxe.macro.Context;
import sys.io.File;

/** Supplies one generated resource whose revision must participate in reuse. **/
class ReuseFixtureMacro {
	/** Installs the deterministic resource consumed by the runtime fixture. **/
	public static function install():Void {
		Context.addResource("reuse-payload", File.getBytes("reuse-resource.txt"));
	}
}
#end
