class StringMain {
	static function main() {
		var s = "abcdef";

		var len = s.length;
		var up = "Abc".toUpperCase();
		var low = "AbC".toLowerCase();
		var c0 = s.charAt(0);
		var cneg = s.charAt(-1);
			var code0:Null<Int> = s.charCodeAt(0);
			var codeOob:Null<Int> = s.charCodeAt(999);

		var idx = s.indexOf("cd");
		var idxFrom = s.indexOf("cd", 3);
		var last = s.lastIndexOf("cd");
		var lastFrom = s.lastIndexOf("cd", 2);

		var parts = "a,b,c".split(",");
		var chars = "abc".split("");

		var sub = s.substr(1, 3);
		var subNeg = s.substr(-2);
		var ss = s.substring(1, 4);
		var ssSwap = s.substring(4, 1);
		var ssNeg = s.substring(-1, 2);

		var fc = String.fromCharCode(len + 65);

		var i = len + 1;
		var b = len > 0;
		var fl:Float = 2.5;
		var concat = "a" + "b" + i + b + fl;

		// Use values so they aren't trivially optimized away.
			if (len == 0 || up == "" || low == "" || c0 == "" || cneg != "" || code0 < 0 || codeOob != null) {
				throw "unexpected";
			}
		if (idx < 0 || idxFrom != -1 || last < 0 || lastFrom != 2) {
			throw "unexpected";
		}
		if (parts.length != 3 || chars.length != 3) {
			throw "unexpected";
		}
		if (sub != "bcd" || subNeg != "ef" || ss != "bcd" || ssSwap != "bcd" || ssNeg != "ab") {
			throw "unexpected";
		}
		if (fc != "G" || concat == "") {
			throw "unexpected";
		}
	}
}
