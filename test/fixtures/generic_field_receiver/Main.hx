/** Keep a field's declaration parameter distinct from its caller's parameter. */
class Node<T> {
	public var value:T;

	public function new(value:T) {
		this.value = value;
	}
}

/** A callback must receive the value type applied to this exact node. */
class Check<T> {
	public function new() {}

	public function apply(node:Node<T>, callback:T->Bool):Bool {
		return callback(node.value);
	}

	public function optional(node:Null<Node<T>>, callback:T->Bool):Bool {
		return node != null && callback(node.value);
	}
}

/** Inherited storage binds against the declaring parent, including reordered arguments. */
class Pair<A, B> {
	public var left:A;
	public var right:B;

	public function new(left:A, right:B) {
		this.left = left;
		this.right = right;
	}
}

/** Bare and qualified inherited reads must produce the same applied member type. */
class Child<X> extends Pair<Int, X> {
	public function new(value:X) {
		super(7, value);
	}

	public function inherited(callback:X->Bool):Bool {
		return callback(right) && callback(this.right);
	}
}

/** Observe generic, nullable, and inherited field reads through the generated target. */
class Main {
	static function matches(value:String):Bool {
		return value == "ok";
	}

	static function main():Void {
		final node = new Node<String>("ok");
		final check = new Check<String>();
		Sys.println(check.apply(node, matches));
		Sys.println(check.optional(node, matches));
		Sys.println(check.optional(null, matches));
		final child = new Child<String>("ok");
		Sys.println(child.inherited(matches));
		Sys.println(child.left);
		Sys.println(child.right);
		Sys.println(new Node<Int>(9).value);
	}
}
