/** A selected String context cannot accept an Int constructor operand. */
class ConstructorConflictCases {
	static function main():Void {
		final box:Box<String> = new Box(7);
	}
}

/** The constructor operand and owner argument must agree before typed publication. */
class Box<T> {
	public function new(value:T) {}
}
