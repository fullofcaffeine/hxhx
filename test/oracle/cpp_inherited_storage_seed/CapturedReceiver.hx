/** An escaping closure must retain the same inherited slot after local object references leave scope. */
class CapturedReceiver {
	static function main():Void {
		var reader:Void->Int;
		{
			final child = new CapturedChild(7);
			final base:CapturedBase = child;
			reader = child.reader;
			base.value = 11;
		}
		if (reader() != 12 || reader() != 13)
			throw "captured inherited field lost identity or state";
	}
}

/** Declares the storage shared by the child, its upcast, and its captured receiver. */
class CapturedBase {
	public var value:Int;

	public function new(seed:Int) {
		value = seed;
	}
}

/** The closure reads and writes the inherited field without an explicit this expression. */
class CapturedChild extends CapturedBase {
	public var reader:Void->Int;

	public function new(seed:Int) {
		super(seed);
		reader = () -> {
			value = value + 1;
			return value;
		};
	}
}
