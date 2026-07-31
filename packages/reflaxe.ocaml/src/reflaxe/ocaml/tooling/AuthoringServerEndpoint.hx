package reflaxe.ocaml.tooling;

using StringTools;

/**
	Validates the local upstream-Haxe compilation server selected by authoring tools.

	The Haxe compilation-server protocol is not an internet-facing authenticated
	service, so the supported package workflow accepts only an unqualified port or
	an explicit IPv4/hostname loopback endpoint. The returned text can be passed
	directly to Haxe's `--connect` option.
**/
class AuthoringServerEndpoint {
	/**
		Returns the Haxe endpoint argument, or `null` when the value is malformed or
		does not identify the local machine.
	**/
	public static function parse(value:String):Null<String> {
		final candidate = value.trim();
		if (candidate.length == 0) {
			return null;
		}

		if (isPort(candidate)) {
			return candidate;
		}

		final separator = candidate.lastIndexOf(":");
		if (separator <= 0 || separator >= candidate.length - 1) {
			return null;
		}
		final host = candidate.substr(0, separator).toLowerCase();
		final port = candidate.substr(separator + 1);
		return (host == "127.0.0.1" || host == "localhost") && isPort(port) ? candidate : null;
	}

	static function isPort(value:String):Bool {
		if (!~/^[0-9]+$/.match(value)) {
			return false;
		}
		final port = Std.parseInt(value);
		return port != null && port >= 1 && port <= 65535;
	}
}
