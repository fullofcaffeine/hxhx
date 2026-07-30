package;

private typedef PlainAnonymousValue = {
	var name:String;
	var count:Int;
	var enabled:Bool;
}

/**
	Provides typed expressions used to verify the anonymous-object boundary.

	The cases deliberately separate a direct object and its local alias from
	same-shaped values whose runtime origin is unknown. The planner should own
	only the first family.
**/
class AnonymousStructurePlanCases {
	public static function admitted():Int {
		var original:PlainAnonymousValue = {name: "first", count: 1, enabled: false};
		var alias = original;
		alias.count = 2;
		alias.enabled = true;
		return original.count;
	}

	public static function parameterOnly(value:PlainAnonymousValue):Int {
		return value.count;
	}

	public static function reassigned(value:PlainAnonymousValue):Int {
		var local:PlainAnonymousValue = {name: "local", count: 1, enabled: false};
		local = value;
		return local.count;
	}

	public static function keyValuePair():Int {
		var entry = {key: "one", value: 1};
		return entry.value;
	}

	public static function methodBearing():Int {
		var value = {read: function() return 1};
		return value.read();
	}
}
