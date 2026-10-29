import model.Types;
import model.Types.PublicLeaf as Alias;

/** Public reflection names and ordinary generic class identity survive lookup. */
class Main {
	// Heterogeneous class handles require this metadata boundary. No instance
	// value becomes Dynamic; the boundary returns only the identity comparison.
	static function sameClass(left:Class<Dynamic>, right:Class<Dynamic>):Bool
		return left == right;

	static function main():Void {
		Sys.println(Type.getClassName(Alias));
		Sys.println(Type.getClassName(Types.hidden()));
		Sys.println(Type.resolveClass("model.PublicLeaf") == Alias);
		Sys.println(Type.resolveClass("model.Types.PublicLeaf") == null);
		Sys.println(Type.resolveClass("not.present.Type") == null);
		Sys.println(sameClass(Type.getClass(new Box<Int>()), Type.getClass(new Box<String>())));
	}
}

/** Type parameters do not specialize this ordinary class at runtime. */
class Box<T> {
	public function new() {}
}
