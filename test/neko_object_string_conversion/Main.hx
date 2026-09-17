/** A receiver-sensitive conversion whose effect is visible after each call. */
class Label {
	public var calls:Int = 0;

	public function new() {}

	public function toString():String {
		calls++;
		return "label";
	}
}

/** The most-derived conversion must be selected through inherited allocation. */
class Child extends Label {
	public override function toString():String {
		calls++;
		return "child";
	}
}

/** Observes object conversion independently of exception handling. */
class Main {
	/** The VM primitive accepts heterogeneous values; contain its native result in String immediately. */
	static function nativeText(value:Dynamic):String {
		return new String(untyped __dollar__string(value));
	}

	static function main():Void {
		final label = new Label();
		Sys.println("std:" + Std.string(label));
		Sys.println("calls:" + label.calls);
		Sys.println("native:" + nativeText(label));
		Sys.println("calls:" + label.calls);
		final child = new Child();
		Sys.println("override:" + nativeText(child));
		Sys.println("child-calls:" + child.calls);
	}
}
