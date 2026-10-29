/** Observe values before byte encoding, which can normalize native string storage. */
class Pr92SubstrDetails {
	static function main():Void {
		var text = 'Aé😀Z';
		var high = text.substr(2, 1);
		var low = text.substr(3, 1);
		Sys.println('high|' + high.length + '|' + high.charCodeAt(0) + '|' + (high == '�'));
		Sys.println('low|' + low.length + '|' + low.charCodeAt(0) + '|' + (low == '�'));
		Sys.println('pair|' + ((high + low) == '😀'));
		Sys.println('slice-high|' + high.substr(0).charCodeAt(0));
		for (p in [0, 1, 2, 3])
			for (n in [-5, -4, -3, -2, -1])
				Sys.println(p + '|' + n + '|' + 'abcdef'.substr(p, n));
		var position:Null<Int> = null;
		Sys.println('null-pos|' + 'abcdef'.substr(position, 2));
	}
}
