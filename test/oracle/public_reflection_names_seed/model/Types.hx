package model;

/** Keeps private declarations accessible through their exact type handles. */
class Types {
	public static function hidden():Class<Hidden>
		return Hidden;

	public static function hiddenEnum():Enum<HiddenEnum>
		return HiddenEnum;
}

/** Public secondary declarations omit their module segment in reflection. */
class PublicLeaf {
	public function new() {}
}

/** A private declaration retains its private module segment. */
private class Hidden {
	public function new() {}
}

/** Enum names follow the same package rule as classes. */
enum PublicEnum {
	One;
}

/** Private enum names retain their declaring module. */
private enum HiddenEnum {
	One;
}

/** Native metadata supplies the public runtime name. */
@:native("RenamedNative") class Renamed {
	public function new() {}
}

/** Specialization requires a distinct generated runtime declaration. */
@:generic class Specialized<T> {
	public var value:T;

	public function new(value:T) {
		this.value = value;
	}
}

/** Ordinary type parameters do not change the runtime class name. */
class Ordinary<T> {
	public var value:T;

	public function new(value:T) {
		this.value = value;
	}
}
