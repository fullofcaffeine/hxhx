/** The operand fixes T to Int before the enclosing Box<Float> context is checked. */
class ConstructorNumericConflictCases {
	static function main():Void {
		final box:Box<Float> = new Box(1);
	}
}

/** Generic owner inference differs from conversion into an explicitly selected Float parameter. */
class Box<T> {
	public function new(value:T) {}
}
