/** Observe signed words without relying on native representation details. */
class Main {
	static function effect(label:String):haxe.Int64 {
		Sys.println(label);
		return haxe.Int64.make(23, -9);
	}

	static function printWords(value:haxe.Int64):Void {
		Sys.println(value.high);
		Sys.println(value.low);
	}

	static function main():Void {
		printWords(haxe.Int64.make(12, -7));
		printWords(haxe.Int64.make(-1, -1));
		printWords(haxe.Int64.make(0x7FFFFFFF, 0x80000000));
		printWords(haxe.Int64.make(0x80000000, 0x7FFFFFFF));
		Sys.println(effect("high receiver").high);
		Sys.println(effect("low receiver").low);
	}
}
