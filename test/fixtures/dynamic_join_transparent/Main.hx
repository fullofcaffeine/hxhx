/**
	A Dynamic value does not widen a method's result or a switch's value, as in Haxe 4.3.7: the
	result monomorph unifies with Dynamic without binding it, so the concrete branches choose the
	type, in either order (haxe.rtti.XmlParser.processElement). A written result type instead
	casts each case to it.
**/
enum Tree {
	Leaf(name:String);
	Node(left:Tree, right:Tree);
}

class Ops {
	static function fail(name:String):Dynamic
		return throw "Invalid " + name;

	/** A `default` case that returns Dynamic, as in processElement. **/
	public static function pick(name:String) {
		return switch (name) {
			case "leaf": Leaf(name);
			case "pair": Node(Leaf("a"), Leaf("b"));
			default: fail(name);
		}
	}

	public static function dynamicFirst(name:String) {
		return switch (name) {
			case "x": fail(name);
			default: Leaf(name);
		}
	}

	public static function ifValue(flag:Bool) {
		return if (flag) Leaf("a") else fail("b");
	}

	public static function returnsDynamicFirst(flag:Bool) {
		if (flag)
			return fail("b");
		return Leaf("a");
	}

	public static function count(flag:Bool) {
		if (flag)
			return fail("b");
		return 3;
	}

	public static function dynamicLocal(flag:Bool) {
		final value:Dynamic = 1;
		return if (flag) value else "s";
	}

	/** A written Dynamic result keeps the Float case as Dynamic. **/
	public static function written(op:String, left:Dynamic, right:Dynamic):Dynamic {
		return switch (op) {
			case "add": left + right;
			case "div": left / right;
			case _: fail(op);
		};
	}

	public static function describe(tree:Tree):String {
		return switch (tree) {
			case Leaf(name): name;
			case Node(_, _): "node";
		}
	}
}

class Main {
	static function main() {
		Sys.println(Ops.describe(Ops.pick("leaf")) + " " + Ops.describe(Ops.pick("pair")) + " " + Ops.describe(Ops.dynamicFirst("y")));
		Sys.println(Ops.describe(Ops.ifValue(true)) + " " + Ops.describe(Ops.returnsDynamicFirst(false)));
		Sys.println(Ops.count(false) + 1);
		Sys.println(Ops.dynamicLocal(false));
		Sys.println(Ops.written("add", 1, 2) + " " + Ops.written("div", 7, 2));
		try {
			Ops.pick("bad");
		} catch (e:Dynamic) {
			Sys.println("caught " + e);
		}
	}
}
