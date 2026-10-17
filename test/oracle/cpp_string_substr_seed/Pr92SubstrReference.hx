/** Black-box reference: bytes and UTF-16 units distinguish native substring indexing. */
class Pr92SubstrReference {
	static var effects:String = "";

	static function receiver(value:String):String {
		effects += "R";
		return value;
	}

	static function start():Int {
		effects += "S";
		return 1;
	}

	static function length():Int {
		effects += "L";
		return 2;
	}

	static function describe(value:String):String {
		if (value == null)
			return "null";
		return haxe.io.Bytes.ofString(value).toHex()
			+ ":"
			+ value.length
			+ ":"
			+ [for (i in 0...value.length) value.charCodeAt(i)].join(",");
	}

	static function main():Void {
		for (s in ["abcdef", "", "Aé😀Z"]) {
			for (p in [-2147483647 - 1, -10, -6, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 2147483647]) {
				Sys.println("omit|" + describe(s) + "|" + p + "|" + describe(s.substr(p)));
				for (n in ([null, -2147483647 - 1, -10, -2, -1, 0, 1, 2, 3, 20, 2147483647] : Array<Null<Int>>))
					Sys.println("len|" + describe(s) + "|" + p + "|" + n + "|" + describe(s.substr(p, n)));
			}
		}
		effects = "";
		Sys.println("effects|" + describe(receiver("abcdef").substr(start(), length())) + "|" + effects);
		effects = "";
		try {
			var value = receiver(null).substr(start(), length());
			Sys.println("null|" + describe(value) + "|" + effects);
		} catch (_:haxe.Exception) {
			Sys.println("null|throw|" + effects);
		}
	}
}
