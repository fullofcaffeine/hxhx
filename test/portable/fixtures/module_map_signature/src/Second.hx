import haxe.ds.StringMap;
import haxe.ds.IntMap;
import haxe.ds.ObjectMap;

/** Its call back to First requires explicit types for both module exports. */
class Second {
	/** Observe producer evaluation while preserving the existing map and module cycle. */
	public static function counted(value:StringMap<String>, effects:Array<Int>):StringMap<String> {
		effects[0]++;
		return First.identity(value);
	}

	public static function roundtrip(value:StringMap<String>):StringMap<String> {
		return First.identity(value);
	}

	public static function integers(value:IntMap<Array<String>>):IntMap<Array<String>> {
		return First.integerIdentity(value);
	}

	public static function objects(value:ObjectMap<Key, String>):ObjectMap<Key, String> {
		return First.objectIdentity(value);
	}

	public static function nested(value:Map<String, Map<Int, String>>):Map<String, Map<Int, String>> {
		return First.nestedIdentity(value);
	}
}
