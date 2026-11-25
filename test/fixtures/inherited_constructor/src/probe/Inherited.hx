package probe;

/**
	Classes that declare no constructor inherit one, as upstream Haxe 4.3.7 records it
	(haxe_ocaml-rten2.5). `M14InheritedConstructorSignatureTest` records upstream's signatures.
**/
class Parent<S> {
	public function new(items:S, count:Int, ?label:String, scale:Float = 1.5) {}
}

class Child<T> extends Parent<Array<T>> {}
class GrandChild extends Child<String> {}

class Own extends Parent<Int> {
	public function new() {
		super(1, 2);
	}
}

class Plain {}
extern class ExternChild extends Parent<Bool> {}
interface Shape {}
