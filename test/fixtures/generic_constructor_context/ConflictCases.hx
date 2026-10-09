/** One constructor occurrence cannot have incompatible owner arguments. */
class ConflictCases {
	static function main():Void {
		final box = new Box();
		box.set("text");
		box.set(7);
	}
}

/** Reusing one receiver must preserve the type selected by its earlier use. */
class Box<T> {
	public function new() {}

	public function set(value:T):Void {}
}
