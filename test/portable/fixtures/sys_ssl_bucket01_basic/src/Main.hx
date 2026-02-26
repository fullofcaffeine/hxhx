#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;

class SysSslBucket01MacroProbe {
	static inline final PREFIX = "HX_SYS_SSL_BUCKET01_";
	static final MODULES:Array<String> = [
		"sys.ssl.Certificate",
		"sys.ssl.Digest",
		"sys.ssl.DigestAlgorithm",
		"sys.ssl.Key",
		"sys.ssl.Socket"
	];

	static function defineKey(moduleName:String):String {
		return PREFIX + moduleName.toUpperCase().split(".").join("_");
	}

	public static function run():Void {
		for (moduleName in MODULES) {
			final moduleTypes = Context.getModule(moduleName);
			if (moduleTypes == null || moduleTypes.length == 0) {
				Context.fatalError("sys_ssl_bucket01_basic: missing module " + moduleName, Context.currentPos());
			}
			Compiler.define(defineKey(moduleName), "1");
		}
		Compiler.define("HX_SYS_SSL_BUCKET01_DONE", "1");
	}
}
#end

class Main {
	static function printStatus(name:String, ok:Bool):Void {
		Sys.println(name + "=" + (ok ? "ok" : "missing"));
	}

	static function main() {
		#if HX_SYS_SSL_BUCKET01_SYS_SSL_CERTIFICATE
		printStatus("sys.ssl.Certificate", true);
		#else
		printStatus("sys.ssl.Certificate", false);
		#end

		#if HX_SYS_SSL_BUCKET01_SYS_SSL_DIGEST
		printStatus("sys.ssl.Digest", true);
		#else
		printStatus("sys.ssl.Digest", false);
		#end

		#if HX_SYS_SSL_BUCKET01_SYS_SSL_DIGESTALGORITHM
		printStatus("sys.ssl.DigestAlgorithm", true);
		#else
		printStatus("sys.ssl.DigestAlgorithm", false);
		#end

		#if HX_SYS_SSL_BUCKET01_SYS_SSL_KEY
		printStatus("sys.ssl.Key", true);
		#else
		printStatus("sys.ssl.Key", false);
		#end

		#if HX_SYS_SSL_BUCKET01_SYS_SSL_SOCKET
		printStatus("sys.ssl.Socket", true);
		#else
		printStatus("sys.ssl.Socket", false);
		#end

		#if HX_SYS_SSL_BUCKET01_DONE
		Sys.println("sys.ssl.bucket01=done");
		#else
		Sys.println("sys.ssl.bucket01=missing");
		#end
	}
}
