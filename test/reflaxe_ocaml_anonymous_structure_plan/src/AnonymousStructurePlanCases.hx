package;

private typedef PlainAnonymousValue = {
	var name:String;
	var count:Int;
	var enabled:Bool;
}

private class StructuralSource {
	public var name:String;
	public var count:Int;
	public var enabled:Bool;

	public function new(name:String, count:Int, enabled:Bool) {
		this.name = name;
		this.count = count;
		this.enabled = enabled;
	}
}

/**
	Provides typed expressions used to verify the anonymous-object boundary.

	The cases deliberately separate a direct object and its local alias from
	same-shaped values whose runtime origin is unknown. The planner should own
	only the first family. Iterator pairs and file metadata also stay outside
	this generic object plan because their existing OCaml representations have
	different behavior and runtime support.
**/
class AnonymousStructurePlanCases {
	public static function admitted():Int {
		var original:PlainAnonymousValue = {name: "first", count: 1, enabled: false};
		var alias = original;
		alias.count += 1;
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

	public static function iteratorShape():Int {
		var iterator:Iterator<Int> = {
			hasNext: function() return false,
			next: function() return 0
		};
		return iterator.next();
	}

	public static function fileStatShape():Int {
		final stamp = Date.fromTime(0);
		var stat:sys.FileStat = {
			gid: 1,
			uid: 2,
			atime: stamp,
			mtime: stamp,
			ctime: stamp,
			size: 3,
			dev: 4,
			ino: 5,
			nlink: 6,
			rdev: 7,
			mode: 8
		};
		return stat.size;
	}

	public static function methodBearing():Int {
		var value = {read: function() return 1};
		return value.read();
	}

	public static function dynamicCrossing():Int {
		var value:Dynamic = {name: "dynamic", count: 1, enabled: false};
		return value.count;
	}

	public static function structuralConversion():Int {
		var value:PlainAnonymousValue = new StructuralSource("converted", 1, false);
		return value.count;
	}

	public static function patternOnly():Int {
		var value:PlainAnonymousValue = {name: "pattern", count: 1, enabled: false};
		return switch (value) {
			case {count: matched}: matched;
		};
	}

	public static function unsupportedCompound():Int {
		var value:PlainAnonymousValue = {name: "multiply", count: 2, enabled: false};
		value.count *= 3;
		return value.count;
	}
}
