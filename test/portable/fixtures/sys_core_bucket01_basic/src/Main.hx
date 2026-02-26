#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;

class SysCoreBucket01MacroProbe {
	static function defineKey(moduleName:String):String {
		return "HX_SYS_CORE_BUCKET01_" + moduleName.toUpperCase().split(".").join("_");
	}

	public static function run():Void {
		final moduleName = "sys.Http";
		final moduleTypes = Context.getModule(moduleName);
		if (moduleTypes == null || moduleTypes.length == 0) {
			Context.fatalError("sys_core_bucket01_basic: missing module " + moduleName, Context.currentPos());
		}
		Compiler.define(defineKey(moduleName), "1");
		Compiler.define("HX_SYS_CORE_BUCKET01_DONE", "1");
	}
}
#end

class Main {
	static function printStatus(name:String, ok:Bool):Void {
		Sys.println(name + "=" + (ok ? "ok" : "missing"));
	}

	static function main() {
		#if HX_SYS_CORE_BUCKET01_SYS_HTTP
		printStatus("sys.Http", true);
		#else
		printStatus("sys.Http", false);
		#end

		final request = new sys.Http("http://127.0.0.1:9/");
		request.setHeader("X-Bucket", "sys-core-01");
		request.setParameter("k", "v");
		Sys.println("sys.Http.instance=ok");

		#if HX_SYS_CORE_BUCKET01_DONE
		Sys.println("sys.core.bucket01=done");
		#else
		Sys.println("sys.core.bucket01=missing");
		#end
	}
}
