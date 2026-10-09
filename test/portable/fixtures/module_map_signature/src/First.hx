import haxe.ds.StringMap;
import haxe.ds.IntMap;
import haxe.ds.ObjectMap;

/** A source alias must preserve the nullable Map storage selected by the mapper. */
typedef NullableMapValue = Map<Int, String>;

/** Passes a standard map through a recursive module group without copying it. */
class First {
	public static function roundtrip(value:StringMap<String>):StringMap<String> {
		return Second.roundtrip(value);
	}

	public static function identity(value:StringMap<String>):StringMap<String> {
		return value;
	}

	/** Omitted references allocate a map; supplied references retain their identity. */
	public static function optional(?value:StringMap<String>):StringMap<String> {
		return value == null ? new StringMap<String>() : Second.roundtrip(value);
	}

	public static function integers(value:IntMap<Array<String>>):IntMap<Array<String>> {
		return Second.integers(value);
	}

	public static function integerIdentity(value:IntMap<Array<String>>):IntMap<Array<String>> {
		return value;
	}

	public static function objects(value:ObjectMap<Key, String>):ObjectMap<Key, String> {
		return Second.objects(value);
	}

	public static function objectIdentity(value:ObjectMap<Key, String>):ObjectMap<Key, String> {
		return value;
	}

	public static function nested(value:Map<String, Map<Int, String>>):Map<String, Map<Int, String>> {
		return Second.nested(value);
	}

	public static function nestedIdentity(value:Map<String, Map<Int, String>>):Map<String, Map<Int, String>> {
		return value;
	}

	/** Nullable abstract maps keep their boxed representation at both boundaries. */
	public static function nullable(value:Null<NullableMapValue>):Null<NullableMapValue> {
		return value;
	}
}
