typedef Reader<T> = {function read():{item:T};}

/** Inherited member views must retain the child allocation's generic argument. */
class Base<T> {
	var value:T;

	public function new(value:T) {
		this.value = value;
	}

	public function read():{item:T} {
		return {item: value};
	}
}

/** Exercise inherited member substitution without redeclaring the method. */
class Child<T> extends Base<T> {
	public function new(value:T) {
		super(value);
	}
}

/** With no operands, the structural result supplies the only concrete type evidence. */
class Empty<T> {
	public function new() {}

	public function read():{item:Null<T>} {
		return {item: null};
	}
}

/** Observe both operand-led and context-only construction through structural results. */
class Main {
	static function make():Reader<String> {
		return new Child("ok");
	}

	static function main():Void {
		Sys.println(make().read().item);
		final empty:Reader<Null<String>> = new Empty();
		Sys.println(empty.read().item == null);
	}
}
