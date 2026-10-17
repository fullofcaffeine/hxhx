/** A parent can read its child's static field after both class declarations exist. */
class StaticCycle {
	static function main():Void {
		Sys.println(new CycleChild().describe() == null);
	}
}

/** Source order puts the child first and must not remove its parent prototype. */
class CycleChild extends CycleParent {
	public static var label:String = "child";

	public function new() {
		super();
	}

	public override function describe():String {
		return super.describe();
	}
}

/** The static value depends on the child, while the child's prototype depends on this class. */
class CycleParent {
	static var label:String = CycleChild.label;

	public function new() {}

	public function describe():String {
		return label;
	}
}
