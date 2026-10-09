/** Stored virtual methods select the actual object's override, including bare reads inside instance methods. */
class FeatureBoundInheritance {
	static function main():Void {
		final child = new BoundChild();
		final base:BoundBase = child;
		final explicit = base.read;
		final implicit = child.capture();
		trace(explicit());
		trace(implicit());
		trace(explicit == implicit);
		child.label = "changed";
		trace(explicit());
		trace(implicit());
	}
}

/** The inherited capture method must use this receiver, not its declaring class. */
class BoundBase {
	public var label:String = "initial";

	public function new() {}

	public function read():String {
		return "base:" + label;
	}

	public function capture():Void->String {
		return read;
	}
}

/** The override reads current receiver state after the callback was stored. */
class BoundChild extends BoundBase {
	public function new() {
		super();
	}

	override public function read():String {
		return "child:" + label;
	}
}
