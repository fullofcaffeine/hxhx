/**
	`value == null` on an untyped input makes it `Null<T>`, where later evidence chooses `T`, as in
	Haxe 4.3.7. A recursive method's call to itself can then bind its result before a return does:
	the parser's `return if (c) a else b` returns once, after the whole `if`.
**/
class Resolver {
	public function new() {}

	public function name():String
		return "r";
}

class Holder {
	public static var resolver:Resolver = new Resolver();
}

class Node {
	public var left:Null<Node>;
	public var value:Int;

	public function new(value:Int, ?left:Node) {
		this.value = value;
		this.left = left;
	}
}

class Ops {
	/** `r` becomes `Null<Resolver>` (haxe.Unserializer.setResolver). **/
	public static function setResolver(r) {
		if (r == null)
			Holder.resolver = new Resolver();
		else
			Holder.resolver = r;
	}

	/** Each operator reads the `Null<fresh>` input as open and binds its inner type. **/
	public static function orZero(x) {
		if (x == null)
			return 0;
		return x + 1;
	}

	public static function scaled(x) {
		if (x == null)
			return 0;
		return x * 2;
	}

	public static function flagged(x) {
		if (x == null)
			return 0;
		return x | 1;
	}

	public static function below(x) {
		if (x == null)
			return false;
		return x < 3;
	}

	/** Both inputs become `Null<Node>` (haxe.ds.BalancedTree.merge). **/
	static function merge(a, b) {
		if (a == null)
			return b;
		if (b == null)
			return a;
		return wrap(b);
	}

	static function wrap(n:Node):Node
		return n;

	/** `wrap(returnIf(...))` binds the result to `Node` before the one return (BalancedTree.removeLoop). **/
	public static function returnIf(c:Int, node:Node) {
		return if (c == 0) merge(node.left, node.left); else wrap(returnIf(c - 1, node));
	}

	/** A return before the recursive call binds the result first: it stays `Null<Node>`. **/
	public static function returnFirst(c:Int, node:Node) {
		if (c == 0)
			return merge(node.left, node.left);
		return wrap(returnFirst(c - 1, node));
	}

	public static function chain(c:Int, node:Node) {
		return if (c == 0) merge(node.left, node.left); else if (c < 0) wrap(chain(c + 1, node)); else wrap(chain(c - 1, node));
	}
}

class Main {
	static function main() {
		Ops.setResolver(null);
		Sys.println(Holder.resolver.name());
		Sys.println(Ops.orZero(null) + " " + Ops.orZero(4));
		Sys.println(Ops.scaled(null) + " " + Ops.scaled(4));
		Sys.println(Ops.flagged(null) + " " + Ops.flagged(4));
		Sys.println(Ops.below(null) + " " + Ops.below(2));
		final root = new Node(1, new Node(7));
		Sys.println(Ops.returnIf(2, root).value + " " + Ops.returnFirst(1, root).value + " " + Ops.chain(-1, root).value);
		Sys.println(Ops.returnFirst(0, new Node(3)) == null);
	}
}
