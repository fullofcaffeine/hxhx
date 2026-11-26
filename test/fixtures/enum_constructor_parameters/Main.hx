/**
	An enum constructor may declare its own type parameters and its result type (GADT style), as in
	Haxe 4.3.7 (haxe_ocaml-lfpdo).
**/
enum E {
	E1<T:String>(v:T);
}

enum Binop<S, T> {
	OpAdd:Binop<Float, Float>;
}

enum Ex<T> {
	EConst(v:T):Ex<T>;
	EBinop<C>(op:Binop<C, T>, e1:Ex<C>, e2:Ex<C>):Ex<T>;
}

abstract Label(String) to String {
	public function new()
		this = "label";
}

class Main {
	static function call<T:Label>(v:T)
		return E1(v);

	static function main() {
		final e = E1("x");
		final b = EBinop(OpAdd, EConst(1.5), EConst(2.5));
		Sys.println((e != null) + " " + (b != null) + " " + (call(new Label()) != null));
	}
}
