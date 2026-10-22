import haxe.ds.Map;

/** A Map destination does not authorize an incompatible entry key. */
class InvalidKey {
	static function main():Void {
		final value:Map<Int, Bool> = ["value" => true];
	}
}
