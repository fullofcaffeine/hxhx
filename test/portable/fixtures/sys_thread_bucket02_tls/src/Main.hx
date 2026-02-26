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

	static function runTlsRuntimeChecks():Void {
		final tls = new sys.thread.Tls<Int>();
		tls.value = 7;

		final done = new sys.thread.Lock();
		var workerValue:Int = -1;
		sys.thread.Thread.create(() -> {
			tls.value = 42;
			workerValue = tls.value;
			done.release();
		});

		final workerDone = done.wait(2.0);
		final mainValue = tls.value;

		printStatus("sys.thread.Tls.runtime.worker", workerDone && workerValue == 42);
		printStatus("sys.thread.Tls.runtime.main", mainValue == 7);
	}

	static function main() {
		#if HX_SYS_THREAD_BUCKET02_SYS_THREAD_TLS_AVAILABLE
		printStatus("sys.thread.Tls", true);
		#elseif HX_SYS_THREAD_BUCKET02_SYS_THREAD_TLS_UNAVAILABLE
		printStatus("sys.thread.Tls", false);
		#else
		printStatus("sys.thread.Tls", false);
		#end

		#if target.threaded
		runTlsRuntimeChecks();
		#end

		#if HX_SYS_THREAD_BUCKET02_DONE
		Sys.println("sys.thread.bucket02=done");
		#else
		Sys.println("sys.thread.bucket02=missing");
		#end
	}
}
