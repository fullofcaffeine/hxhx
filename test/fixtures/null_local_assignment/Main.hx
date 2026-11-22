/**
	A local declared as bare `null` is a nullable monomorph in Haxe 4.3.7. The first assigned value
	gives it a type, and a generic constructor assigned to it takes its type arguments from later
	uses. `haxe.rtti.XmlParser` relies on both: `var args = null; ... args = new Array();
	args.push({...});` in `xenumfield`, and `var t = null; ... t = xtype(c); types.set(p, t);` in
	`xtypedef`. An object literal assigned to such a local still has its fields checked by later
	uses, as in `haxe.macro.MacroStringTools.toFieldExpr`.
**/
typedef Arg = {name:String, opt:Bool};
typedef Field = {name:String, args:Null<Array<Arg>>};
typedef Definition = {doc:Null<String>, types:haxe.ds.StringMap<Int>};

class Defs {
	public static function arity(f:Field):Int
		return f.args == null ? -1 : f.args.length;

	public static function sizes(d:Definition):Int {
		var total = 0;
		for (size in d.types)
			total += size;
		return total;
	}
}

// typing-only:begin

/**
	The `haxe.macro.MacroStringTools.toFieldExpr` shape: an object literal assigned to a `null`
	local feeds an enum constructor that expects the declared structure, and the untyped `?pos`
	gets its type from the result.
**/
enum Shape {
	Leaf(name:String);
	Member(of:Node, name:String);
}

typedef Node = {shape:Shape, pos:Int};

class Paths {
	public static function path(names:Array<String>, ?pos):Node {
		var e = null;
		for (v in names)
			if (e == null)
				e = {shape: Leaf(v), pos: pos};
			else
				e = {shape: Member(e, v), pos: pos};
		return e;
	}

	public static function depth(node:Node):Int
		return switch node.shape {
			case Leaf(_): 1;
			case Member(of, _): 1 + depth(of);
		};
}

// typing-only:end

/** The observed operations take simple inputs; `Defs` holds the declared structures. **/
class Ops {
	public static function field(first:String, second:String, has:Bool) {
		var args = null;
		if (has) {
			args = new Array();
			args.push({name: first, opt: false});
			args.push({name: second, opt: true});
		}
		return Defs.arity({name: "f", args: args});
	}

	public static function definition(items:Array<String>, platform:Null<String>) {
		var doc = null;
		var t = null;
		for (c in items)
			if (c == "doc")
				doc = c;
			else
				t = c.length;
		var types = new haxe.ds.StringMap();
		if (platform != null)
			types.set(platform, t);
		return Defs.sizes({doc: doc, types: types});
	}
}

class Main {
	static function main() {
		Sys.println(Ops.field("a", "b", true));
		Sys.println(Ops.field("a", "b", false));
		Sys.println(Ops.definition(["doc", "abc"], "p"));
		Sys.println(Ops.definition(["x"], null));
	}
}
