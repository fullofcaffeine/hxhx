package sys.net;

/**
	OCaml target override for `sys.net.Host`.

	Why
	- Upstream declares `Host` as extern.
	- reflaxe.ocaml currently needs a concrete class surface so portable fixtures can
	  instantiate `Host` without depending on host-native socket bindings.

	What
	- Keeps the upstream API shape (`host`, `ip`, `new`, `toString`, `reverse`,
	  `localhost`) and provides deterministic fallback behavior.
	- `ip` is best-effort parsed from dotted IPv4 text; unresolved names map to `0`.
**/
class Host {
	public var host(default, null):String;
	public var ip(default, null):Int;

	public function new(name:String):Void {
		host = name;
		init(resolve(name));
	}

	public function toString():String {
		return host == null ? hostToString(ip) : host;
	}

	public function reverse():String {
		return hostReverse(ip);
	}

	public static function localhost():String {
		return "localhost";
	}

	function init(ip:Int):Void {
		this.ip = ip;
	}

	static function resolve(value:String):Int {
		if (value == null)
			return 0;
		final parts = value.split(".");
		if (parts.length != 4)
			return 0;
		var acc = 0;
		for (part in parts) {
			final octet = Std.parseInt(part);
			if (octet == null || octet < 0 || octet > 255)
				return 0;
			acc = (acc << 8) | octet;
		}
		return acc;
	}

	static function hostToString(ip:Int):String {
		final a = (ip >> 24) & 255;
		final b = (ip >> 16) & 255;
		final c = (ip >> 8) & 255;
		final d = ip & 255;
		return '$a.$b.$c.$d';
	}

	static function hostReverse(ip:Int):String {
		return hostToString(ip);
	}
}
