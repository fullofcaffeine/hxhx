using StringTools;

/**
	Runs the String API on text with one-, two-, three- and four-byte UTF-8
	characters. Upstream Haxe 4.3.7 (eval) counts Unicode code points, so every
	index, length, and character code below is a code-point value.

	String iteration and `StringTools.replace` are checked by the reflaxe.ocaml
	portable fixture `string_unicode_code_points`, which also runs this class.
	Stage3 cannot run them yet: see this fixture's README.
**/
class Main {
	static function codes(s:String):String {
		final out = [];
		for (index in 0...s.length)
			out.push(Std.string(s.charCodeAt(index)));
		return out.join(",");
	}

	static function show(label:String, s:String):Void {
		Sys.println(label + " length=" + s.length + " upper=" + s.toUpperCase() + " lower=" + s.toLowerCase());
		Sys.println(label + " charAt=" + s.charAt(1) + "|" + s.charAt(5) + "|" + s.charAt(6) + "|" + s.charAt(7) + "|" + s.charAt(-1));
		Sys.println(label + " charCodeAt=" + s.charCodeAt(1) + "," + s.charCodeAt(5) + "," + s.charCodeAt(6) + "," + s.charCodeAt(7));
		Sys.println(label + " indexOf=" + s.indexOf("l") + "," + s.indexOf("l", 3) + "," + s.indexOf("😀") + "," + s.indexOf("漢") + "," + s.indexOf("", 3)
			+ "," + s.indexOf("x"));
		Sys.println(label
			+ " lastIndexOf="
			+ s.lastIndexOf("l")
			+ ","
			+ s.lastIndexOf("l", 2)
			+ ","
			+ s.lastIndexOf("é")
			+ ","
			+ s.lastIndexOf("😀", 5));
		Sys.println(label + " substr=" + s.substr(1, 3) + "|" + s.substr(-2) + "|" + s.substr(5) + "|" + s.substr(5, 1));
		Sys.println(label + " substring=" + s.substring(4, 6) + "|" + s.substring(6, 1) + "|" + s.substring(5));
		Sys.println(label + " split=" + s.split("l").join("/") + "|" + s.split("").join("/") + "|" + s.split("😀").join("/"));
		Sys.println(label + " codes=" + codes(s));
	}

	public static function main():Void {
		show("mixed", "héllo😀漢");
		Sys.println("fromCharCode=" + String.fromCharCode(233) + String.fromCharCode(0x6F22) + String.fromCharCode(0x1F600) + " length="
			+ String.fromCharCode(0x1F600).length);
		Sys.println("case=" + "ÀÉÎÕÜ".toLowerCase() + " " + "àéîõü".toUpperCase() + " " + "ΑΒΓ σς".toUpperCase() + " " + "ДЖЯ".toLowerCase() + " "
			+ "ß".toUpperCase() + " " + "ǆ".toUpperCase() + " " + "İ".toLowerCase());
		final s = "héllo😀漢";
		Sys.println("fastCodeAt=" + StringTools.fastCodeAt(s, 5) + "," + StringTools.fastCodeAt(s, 6) + ","
			+ StringTools.isEof(StringTools.fastCodeAt(s, 7)) + " unsafeCodeAt=" + StringTools.unsafeCodeAt(s, 1));
		Sys.println("tools=" + StringTools.lpad("é", "ü", 3) + "|" + StringTools.rpad("漢", "😀", 3) + "|" + StringTools.trim("  é😀  ") + "|"
			+ StringTools.startsWith(s, "hé") + "|" + StringTools.endsWith(s, "😀漢") + "|" + StringTools.contains(s, "😀") + "|"
			+ StringTools.isSpace("é ", 1) + "|" + StringTools.htmlEscape("é<😀>"));
		Sys.println("compare=" + ("é" < "z") + "," + ("😀" > "漢") + "," + ("a" < "é") + "," + ("漢" < "😀") + "," + ("é" == "é"));
		final buf = new StringBuf();
		buf.addChar(233);
		buf.addChar(0x1F600);
		buf.add("x");
		buf.addSub("héllo", 1, 2);
		Sys.println("buf=" + buf.toString() + " length=" + buf.length);
		var caseSum = 0;
		var changed = 0;
		var code = 0;
		while (code < 0x110000) {
			if (code < 0xD800 || code > 0xDFFF) {
				final text = String.fromCharCode(code);
				final upper = text.toUpperCase();
				final lower = text.toLowerCase();
				if (upper != text || lower != text) {
					changed++;
					final upperCode = StringTools.fastCodeAt(upper, 0);
					final lowerCode = StringTools.fastCodeAt(lower, 0);
					caseSum = (caseSum * 31 + code * 7 + upperCode * 3 + lowerCode) % 1000000007;
				}
			}
			code++;
		}
		Sys.println("case-table changed=" + changed + " checksum=" + caseSum);
		var long = "";
		for (i in 0...40)
			long += "aé漢😀";
		Sys.println("long length=" + long.length + " at=" + long.charCodeAt(157) + "," + long.charCodeAt(158) + "," + long.charCodeAt(159) + " index="
			+ long.lastIndexOf("é") + " sub=" + long.substring(150, 154));
	}
}
