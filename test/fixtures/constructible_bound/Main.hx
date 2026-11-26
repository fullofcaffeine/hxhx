import haxe.Constraints.Constructible;
import haxe.Constraints.IMap;
import haxe.ds.EnumValueMap;

/**
	A `Constructible<F>` bound is satisfied by a class whose public constructor, its own or an
	inherited one, fits F (haxe_ocaml-g3l8y).
**/
class Parent {
	public function new() {}
}

class Child extends Parent {}

class TakeParent {
	public var name:String;

	public function new(parent:Parent) {
		name = "TakeParent";
	}
}

class TakeChild extends TakeParent {
	public function new(child:Child) {
		super(child);
		name = "TakeChild";
	}
}

class Inherits extends TakeParent {}

enum En {
	A;
}

@:generic
class VarManager<K, M:IMap<K, String> & Constructible<() -> Void>> {
	public function new() {}

	public function name()
		return "manager";
}

class Main {
	@:generic static function get<Arg, Cls:Constructible<Arg->Void>>(a:Arg, c:Class<Cls>):Cls
		return new Cls(a);

	static final manager:VarManager<En, EnumValueMap<En, String>> = new VarManager();

	static function main() {
		Sys.println(get(new Parent(), TakeParent).name + " " + get(new Child(), TakeChild).name + " " + get(new Child(), TakeParent).name);
		Sys.println(get(new Parent(), Inherits).name + " " + manager.name());
	}
}
