#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;

class SysThreadBucket02MacroProbe {
	static inline final PREFIX = "HX_SYS_THREAD_BUCKET02_";

	public static function run():Void {
		if (Context.defined("target.threaded")) {
			Compiler.define(PREFIX + "SYS_THREAD_TLS_AVAILABLE", "1");
		} else {
			Compiler.define(PREFIX + "SYS_THREAD_TLS_UNAVAILABLE", "1");
		}
		Compiler.define(PREFIX + "DONE", "1");
	}
}
#end

class Main {
	static function printStatus(name:String, ok:Bool):Void {
		Sys.println(name + "=" + (ok ? "ok" : "missing"));
	}

	static function main() {
		#if HX_SYS_THREAD_BUCKET02_SYS_THREAD_TLS_AVAILABLE
		printStatus("sys.thread.Tls", true);
		#elseif HX_SYS_THREAD_BUCKET02_SYS_THREAD_TLS_UNAVAILABLE
		printStatus("sys.thread.Tls", false);
		#else
		printStatus("sys.thread.Tls", false);
		#end

		#if HX_SYS_THREAD_BUCKET02_DONE
		Sys.println("sys.thread.bucket02=done");
		#else
		Sys.println("sys.thread.bucket02=missing");
		#end
	}
}
