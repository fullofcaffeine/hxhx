/** Parameterized generic constructor control for the Cpp constructor oracle. **/
class GenericCell<T> {
	public final value:T;
	public final next:Null<GenericCell<T>>;

	public function new(value:T, next:Null<GenericCell<T>>) {
		this.value = value;
		this.next = next;
	}
}

/** Zero-argument generic constructor whose behavior must not inherit sibling args. **/
class GenericStack<T> {
	var head:Null<GenericCell<T>>;

	public function new() {}

	public function add(value:T):Void {
		head = new GenericCell(value, head);
	}

	public function first():Null<T> {
		return head == null ? null : head.value;
	}

	public function isEmpty():Bool {
		return head == null;
	}
}

/** Unrelated non-generic zero-argument constructor control. **/
class PlainZero {
	public final marker:Int;

	public function new() {
		marker = 7;
	}
}

/**
	Repo-owned upstream Haxe oracle for generic constructor ownership and arity.

	The cases record observable behavior only and do not copy upstream tests.
**/
class Main {
	static function emit(id:String, value:Dynamic):Void {
		Sys.println(id + "|value|" + Std.string(value));
	}

	static function main():Void {
		final stack = new GenericStack<Int>();
		emit("generic-ctor-01:zero-empty", stack.isEmpty());
		emit("generic-ctor-01:zero-first-null", stack.first() == null);
		stack.add(4);
		emit("generic-ctor-01:zero-push-first", stack.first());

		final cell = new GenericCell<String>("node", null);
		emit("generic-ctor-01:param-value", cell.value);
		emit("generic-ctor-01:param-next-null", cell.next == null);

		emit("generic-ctor-01:plain-zero", new PlainZero().marker);
	}
}
