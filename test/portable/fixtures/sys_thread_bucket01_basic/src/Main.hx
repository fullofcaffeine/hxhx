#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;

class SysThreadBucket01MacroProbe {
	static inline final PREFIX = "HX_SYS_THREAD_BUCKET01_";
	static inline final AVAILABLE = "_AVAILABLE";
	static inline final UNAVAILABLE = "_UNAVAILABLE";
	static final MODULES:Array<String> = [
		"sys.thread.Condition",
		"sys.thread.Deque",
		"sys.thread.ElasticThreadPool",
		"sys.thread.EventLoop",
		"sys.thread.FixedThreadPool",
		"sys.thread.IThreadPool",
		"sys.thread.Lock",
		"sys.thread.Mutex",
		"sys.thread.NoEventLoopException",
		"sys.thread.Semaphore",
		"sys.thread.Thread",
		"sys.thread.ThreadPoolException"
	];

	static function defineKey(moduleName:String):String {
		return PREFIX + moduleName.toUpperCase().split(".").join("_");
	}

	public static function run():Void {
		final threadedTarget = Context.defined("target.threaded");
		for (moduleName in MODULES) {
			final key = defineKey(moduleName);
			if (threadedTarget) {
				Compiler.define(key + AVAILABLE, "1");
			} else {
				Compiler.define(key + UNAVAILABLE, "1");
			}
		}
		Compiler.define("HX_SYS_THREAD_BUCKET01_DONE", "1");
	}
}
#end

class Main {
	static function printStatus(name:String, ok:Bool):Void {
		Sys.println(name + "=" + (ok ? "ok" : "missing"));
	}

	static function main() {
		#if HX_SYS_THREAD_BUCKET01_SYS_THREAD_CONDITION_AVAILABLE
		printStatus("sys.thread.Condition", true);
		#elseif HX_SYS_THREAD_BUCKET01_SYS_THREAD_CONDITION_UNAVAILABLE
		printStatus("sys.thread.Condition", false);
		#else
		printStatus("sys.thread.Condition", false);
		#end

		#if HX_SYS_THREAD_BUCKET01_SYS_THREAD_DEQUE_AVAILABLE
		printStatus("sys.thread.Deque", true);
		#elseif HX_SYS_THREAD_BUCKET01_SYS_THREAD_DEQUE_UNAVAILABLE
		printStatus("sys.thread.Deque", false);
		#else
		printStatus("sys.thread.Deque", false);
		#end

		#if HX_SYS_THREAD_BUCKET01_SYS_THREAD_ELASTICTHREADPOOL_AVAILABLE
		printStatus("sys.thread.ElasticThreadPool", true);
		#elseif HX_SYS_THREAD_BUCKET01_SYS_THREAD_ELASTICTHREADPOOL_UNAVAILABLE
		printStatus("sys.thread.ElasticThreadPool", false);
		#else
		printStatus("sys.thread.ElasticThreadPool", false);
		#end

		#if HX_SYS_THREAD_BUCKET01_SYS_THREAD_EVENTLOOP_AVAILABLE
		printStatus("sys.thread.EventLoop", true);
		#elseif HX_SYS_THREAD_BUCKET01_SYS_THREAD_EVENTLOOP_UNAVAILABLE
		printStatus("sys.thread.EventLoop", false);
		#else
		printStatus("sys.thread.EventLoop", false);
		#end

		#if HX_SYS_THREAD_BUCKET01_SYS_THREAD_FIXEDTHREADPOOL_AVAILABLE
		printStatus("sys.thread.FixedThreadPool", true);
		#elseif HX_SYS_THREAD_BUCKET01_SYS_THREAD_FIXEDTHREADPOOL_UNAVAILABLE
		printStatus("sys.thread.FixedThreadPool", false);
		#else
		printStatus("sys.thread.FixedThreadPool", false);
		#end

		#if HX_SYS_THREAD_BUCKET01_SYS_THREAD_ITHREADPOOL_AVAILABLE
		printStatus("sys.thread.IThreadPool", true);
		#elseif HX_SYS_THREAD_BUCKET01_SYS_THREAD_ITHREADPOOL_UNAVAILABLE
		printStatus("sys.thread.IThreadPool", false);
		#else
		printStatus("sys.thread.IThreadPool", false);
		#end

		#if HX_SYS_THREAD_BUCKET01_SYS_THREAD_LOCK_AVAILABLE
		printStatus("sys.thread.Lock", true);
		#elseif HX_SYS_THREAD_BUCKET01_SYS_THREAD_LOCK_UNAVAILABLE
		printStatus("sys.thread.Lock", false);
		#else
		printStatus("sys.thread.Lock", false);
		#end

		#if HX_SYS_THREAD_BUCKET01_SYS_THREAD_MUTEX_AVAILABLE
		printStatus("sys.thread.Mutex", true);
		#elseif HX_SYS_THREAD_BUCKET01_SYS_THREAD_MUTEX_UNAVAILABLE
		printStatus("sys.thread.Mutex", false);
		#else
		printStatus("sys.thread.Mutex", false);
		#end

		#if HX_SYS_THREAD_BUCKET01_SYS_THREAD_NOEVENTLOOPEXCEPTION_AVAILABLE
		printStatus("sys.thread.NoEventLoopException", true);
		#elseif HX_SYS_THREAD_BUCKET01_SYS_THREAD_NOEVENTLOOPEXCEPTION_UNAVAILABLE
		printStatus("sys.thread.NoEventLoopException", false);
		#else
		printStatus("sys.thread.NoEventLoopException", false);
		#end

		#if HX_SYS_THREAD_BUCKET01_SYS_THREAD_SEMAPHORE_AVAILABLE
		printStatus("sys.thread.Semaphore", true);
		#elseif HX_SYS_THREAD_BUCKET01_SYS_THREAD_SEMAPHORE_UNAVAILABLE
		printStatus("sys.thread.Semaphore", false);
		#else
		printStatus("sys.thread.Semaphore", false);
		#end

		#if HX_SYS_THREAD_BUCKET01_SYS_THREAD_THREAD_AVAILABLE
		printStatus("sys.thread.Thread", true);
		#elseif HX_SYS_THREAD_BUCKET01_SYS_THREAD_THREAD_UNAVAILABLE
		printStatus("sys.thread.Thread", false);
		#else
		printStatus("sys.thread.Thread", false);
		#end

		#if HX_SYS_THREAD_BUCKET01_SYS_THREAD_THREADPOOLEXCEPTION_AVAILABLE
		printStatus("sys.thread.ThreadPoolException", true);
		#elseif HX_SYS_THREAD_BUCKET01_SYS_THREAD_THREADPOOLEXCEPTION_UNAVAILABLE
		printStatus("sys.thread.ThreadPoolException", false);
		#else
		printStatus("sys.thread.ThreadPoolException", false);
		#end

		#if HX_SYS_THREAD_BUCKET01_DONE
		Sys.println("sys.thread.bucket01=done");
		#else
		Sys.println("sys.thread.bucket01=missing");
		#end
	}
}
