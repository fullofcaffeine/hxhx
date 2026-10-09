/** Dynamic crosses an erased runtime boundary that the current C++ Map carrier cannot inspect. */
class Main {
	static function check(value:Dynamic):Bool {
		return value is haxe.ds.IntMap;
	}

	static function main():Void {
		Sys.println(check([1 => "one"]));
	}
}
