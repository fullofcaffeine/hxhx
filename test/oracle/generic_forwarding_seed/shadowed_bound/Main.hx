/** A same-spelled class cannot satisfy an arbitrary caller parameter. */
class Main {
	static function requireObject<T:{}, S:T>(value:T, other:S):S {
		return other;
	}

	static function make():Box {
		return new Box();
	}

	static function forward<Box:{}>(value:Box):Main.Box {
		return requireObject(value, make());
	}

	static function main():Void {}
}

/** Its spelling intentionally matches the forwarder's unrelated parameter. */
class Box {
	public function new() {}
}
