/**
	An extractor pattern binds its sub-pattern with the extractor's result, as in Haxe 4.3.7:
	`case Wrap(_.get() => items)` reads `_.get()` on the matched `Box<Array<String>>`, so `items` is an
	Array<String>. haxe.macro.TypeTools matches `TAnonymous(_.get() => {fields: fields})` this way.
	The operations live in their own class, declared before `Main`, so that calls from `main`
	cannot supply the evidence.
**/
class Box<T> {
	public final value:T;

	public function new(value:T)
		this.value = value;

	public function get():T
		return value;
}

enum Holder {
	Wrap(box:Box<Array<String>>);
	Empty;
}

class Ops {
	/** `extra` is an Int only when `items` is an Array. **/
	public static function count(holder:Holder, extra)
		return switch holder {
			case Wrap(_.get() => items): items.length + extra;
			case Empty: extra;
		}

	/** `suffix` is a String only when `items` is an Array<String>. **/
	public static function names(holder:Holder, suffix)
		return switch holder {
			case Wrap(_.get() => items): [for (item in items) item + suffix];
			case Empty: [];
		}
}

class Main {
	static function main() {
		Sys.println(Ops.count(Wrap(new Box(["a", "b"])), 1));
		Sys.println(Ops.count(Empty, 5));
		Sys.println(Ops.names(Wrap(new Box(["x", "y"])), "!").join(","));
	}
}
