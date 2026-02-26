#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;

class SysNetBucket01MacroProbe {
	static inline final PREFIX = "HX_SYS_NET_BUCKET01_";
	static final MODULES:Array<String> = ["sys.net.Address", "sys.net.Host", "sys.net.Socket", "sys.net.UdpSocket"];

	static function defineKey(moduleName:String):String {
		return PREFIX + moduleName.toUpperCase().split(".").join("_");
	}

	public static function run():Void {
		for (moduleName in MODULES) {
			final moduleTypes = Context.getModule(moduleName);
			if (moduleTypes == null || moduleTypes.length == 0) {
				Context.fatalError("sys_net_bucket01_basic: missing module " + moduleName, Context.currentPos());
			}
			Compiler.define(defineKey(moduleName), "1");
		}
		Compiler.define("HX_SYS_NET_BUCKET01_DONE", "1");
	}
}
#end

class Main {
	static function printStatus(name:String, ok:Bool):Void {
		Sys.println(name + "=" + (ok ? "ok" : "missing"));
	}

	static function main() {
		#if HX_SYS_NET_BUCKET01_SYS_NET_ADDRESS
		printStatus("sys.net.Address", true);
		#else
		printStatus("sys.net.Address", false);
		#end

		#if HX_SYS_NET_BUCKET01_SYS_NET_HOST
		printStatus("sys.net.Host", true);
		#else
		printStatus("sys.net.Host", false);
		#end

		#if HX_SYS_NET_BUCKET01_SYS_NET_SOCKET
		printStatus("sys.net.Socket", true);
		#else
		printStatus("sys.net.Socket", false);
		#end

		#if HX_SYS_NET_BUCKET01_SYS_NET_UDPSOCKET
		printStatus("sys.net.UdpSocket", true);
		#else
		printStatus("sys.net.UdpSocket", false);
		#end

		#if HX_SYS_NET_BUCKET01_DONE
		Sys.println("sys.net.bucket01=done");
		#else
		Sys.println("sys.net.bucket01=missing");
		#end

		try {
			final host = new sys.net.Host("127.0.0.1");
			Sys.println("sys.net.Host.runtime=" + (host != null ? "ok" : "missing"));
		} catch (_:haxe.Exception) {
			Sys.println("sys.net.Host.runtime=unavailable");
		}

		try {
			final socket = new sys.net.Socket();
			Sys.println("sys.net.Socket.runtime=" + (socket != null ? "ok" : "missing"));
			socket.close();
		} catch (_:haxe.Exception) {
			Sys.println("sys.net.Socket.runtime=unavailable");
		}

		try {
			final udpSocket = new sys.net.UdpSocket();
			Sys.println("sys.net.UdpSocket.runtime=" + (udpSocket != null ? "ok" : "missing"));
			udpSocket.close();
		} catch (_:haxe.Exception) {
			Sys.println("sys.net.UdpSocket.runtime=unavailable");
		}
	}
}
