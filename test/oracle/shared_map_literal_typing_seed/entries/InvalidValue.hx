import haxe.ds.Map;

/** A Map destination does not authorize an incompatible entry value. */
class InvalidValue {
	static function main():Void {
		final value:Map<String, Bool> = ["value" => 1.5];
	}
}
