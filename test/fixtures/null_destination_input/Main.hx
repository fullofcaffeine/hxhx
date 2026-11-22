/**
	An untyped argument whose first evidence is an assignment to a `Null<T>` destination takes
	`Null<T>`, as Haxe 4.3.7's unify binds an unbound monomorph to the whole destination
	(`haxe.io.Path.withExtension`: `s.ext = ext` with `ext:Null<String>`). An argument that an
	earlier use already bound keeps its type.
**/
class Counter {
	public var count:Null<Int>;
	public var label:Null<String>;

	public function new() {}

	public function show():String
		return (count == null ? "none" : "" + count) + "/" + (label == null ? "-" : label);
}

/** The observed operations take untyped inputs; `Counter` holds the nullable destinations. **/
class Ops {
	public static function setCount(c) {
		final counter = new Counter();
		counter.count = c;
		return counter.show();
	}

	public static function withLabel(ext) {
		final counter = new Counter();
		counter.label = ext;
		return counter.show();
	}

	public static function boundFirst(c) {
		final doubled = c * 2;
		final counter = new Counter();
		counter.count = c;
		return counter.show() + ":" + doubled;
	}
}

class Main {
	static function main() {
		Sys.println(Ops.setCount(null));
		Sys.println(Ops.setCount(3));
		Sys.println(Ops.withLabel(null));
		Sys.println(Ops.withLabel("txt"));
		Sys.println(Ops.boundFirst(4));
	}
}
