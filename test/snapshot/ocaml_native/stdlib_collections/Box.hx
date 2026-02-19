import ocaml.Array;
import ocaml.Hashtbl;

class Box {
	public final a:Array<Int>;
	public final h:Hashtbl<String, Int>;

	public function new(a:Array<Int>, h:Hashtbl<String, Int>) {
		this.a = a;
		this.h = h;
	}
}
