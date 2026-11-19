/**
	Haxe 4.3.7 accepts abstract classes: `abstract class`, `private abstract class`, and
	`abstract private class`, with members such as `abstract function f():T;`,
	`public abstract function`, and `abstract public function`. An abstract member has no body.

	The hxhx parser read `abstract` before `class` as the start of an abstract type, so it failed
	with "Expected abstract name". Eight upstream unit-suite modules failed for this reason
	(haxe_ocaml-rsbh4). The `abstract Name(T)` type declaration must keep its own meaning.
**/
class M14AbstractClassParseTest {
	static final source = "package p;

interface I<T> {
	function get():T;
}

private abstract class Base<T> implements I<T> {
	public function new() {}

	abstract public function get():T;

	public abstract function name():String;

	abstract function kind<K>(k:K):K;

	public function twice():Array<T> {
		return [get(), get()];
	}
}

abstract private class Middle extends Base<Int> {
	public function name():String
		return \"middle\";
}

class Impl extends Middle {
	public function new() {
		super();
	}

	public function get():Int
		return 21;

	function kind<K>(k:K):K
		return k;
}

abstract Meters(Int) from Int {
	public inline function value():Int
		return this;
}
";

	static function find(classes:Array<HxClassDecl>, name:String):HxClassDecl {
		for (c in classes)
			if (HxClassDecl.getName(c) == name)
				return c;
		throw "missing declaration " + name + " in " + [for (c in classes) HxClassDecl.getName(c)];
	}

	static function isAbstractType(c:HxClassDecl):Bool {
		return HxClassDecl.getMetadata(c).indexOf("__hxhx_abstract") >= 0;
	}

	static function isAbstractClass(c:HxClassDecl):Bool {
		return HxClassDecl.getMetadata(c).indexOf("abstract") >= 0;
	}

	static function bodies(c:HxClassDecl):String {
		return [
			for (fn in HxClassDecl.getFunctions(c))
				HxFunctionDecl.getName(fn) + (HxFunctionDecl.getHasBody(fn) ? "+" : "-")
		].join(",");
	}

	static function check(label:String, condition:Bool):Void {
		if (!condition)
			throw label;
	}

	static function main():Void {
		final decl = try ParserStage.parse(source, "p/Main.hx").getDecl() catch (e:haxe.Exception) throw "parse failed: " + e.message;
		final classes = HxModuleDecl.getClasses(decl);

		final names = [for (c in classes) HxClassDecl.getName(c)].join(",");
		check("declarations: " + names, names == "I,Base,Middle,Impl,Meters");

		final base = find(classes, "Base");
		check("Base is a class, not an abstract type", !isAbstractType(base) && !HxClassDecl.getIsInterface(base));
		check("Base is marked abstract", isAbstractClass(base));
		check("Base is private", HxClassDecl.getVisibility(base) == Private);
		check("Base implements I", HxClassDecl.getImplementsPaths(base).length == 1);
		check("Base members: " + bodies(base), bodies(base) == "new+,get-,name-,kind-,twice+");

		final middle = find(classes, "Middle");
		check("Middle is an abstract private class", isAbstractClass(middle)
			&& !isAbstractType(middle)
			&& HxClassDecl.getVisibility(middle) == Private);
		check("Middle extends Base", StringTools.startsWith(HxClassDecl.getExtendsPath(middle), "Base"));
		check("Middle members: " + bodies(middle), bodies(middle) == "name+");

		final impl = find(classes, "Impl");
		check("Impl is not abstract", !isAbstractClass(impl) && !isAbstractType(impl));
		check("Impl extends Middle", HxClassDecl.getExtendsPath(impl) == "Middle");

		check("Meters stays an abstract type", isAbstractType(find(classes, "Meters")));
		check("I stays an interface", HxClassDecl.getIsInterface(find(classes, "I")));

		Sys.println("M14_ABSTRACT_CLASS_PARSE:PASS");
	}
}
