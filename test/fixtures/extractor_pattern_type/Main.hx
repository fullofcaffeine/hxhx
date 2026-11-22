/**
	An extractor pattern binds its sub-pattern with the extractor's result, as in Haxe 4.3.7:
	`case Wrap(_.get() => items)` reads `_.get()` on the matched `Box<Array<String>>`, so `items` is an
	Array<String>. haxe.macro.TypeTools matches `TAnonymous(_.get() => {fields: fields})` this way,
	on the structural `Ref` typedef.
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

/** `haxe.macro.Type.Ref` is structural: `get` is a method field of a typedef, not of a class. **/
typedef Ref<T> = {
	function get():T;
	function toString():String;
}

enum Kind {
	Anonymous(ref:Ref<{fields:Array<String>}>);
	Other;
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

	/**
		The `TypeTools.toComplexType` shape: a structural receiver, a structure sub-pattern, and a
		loop over the bound field. `suffix` is a String only when `fields` is an Array<String>.
	**/
	public static function fieldNames(kind:Kind, suffix)
		return switch kind {
			case Anonymous(_.get() => {fields: fields}): [for (field in fields) field + suffix];
			case Other: [];
		}
}

class Main {
	static function main() {
		Sys.println(Ops.count(Wrap(new Box(["a", "b"])), 1));
		Sys.println(Ops.count(Empty, 5));
		Sys.println(Ops.names(Wrap(new Box(["x", "y"])), "!").join(","));
		Sys.println(Ops.fieldNames(Anonymous({get: () -> {fields: ["p", "q"]}, toString: () -> "ref"}), "?").join(","));
	}
}
