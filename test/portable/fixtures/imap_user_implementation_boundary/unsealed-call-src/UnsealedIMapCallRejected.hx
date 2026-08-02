import haxe.Constraints.IMap;

/** Proves that a static-initializer interface call cannot bypass function planning. */
class UnsealedIMapCallRejected {
	static final map:IMap<String, Int> = null;
	static final value = map.get("missing");

	static function main():Void {}
}
