/** Runtime class tests must use exact typed class operands in JavaScript. */
class Main {
	static final startup = new Child() is Root;
	static final selected:Class<Parent> = Parent;

	static function effect():Parent {
		Sys.println("effect");
		return new Child();
	}

	static function check(value:Parent):Bool
		return value is Root;

	static function main():Void {
		final value = new Child();
		Sys.println(value is Parent);
		Sys.println(value is Other);
		Sys.println(value is Root);
		Sys.println(value is Branch);
		Sys.println(value is Unrelated);
		Sys.println(null is Parent);
		Sys.println(Parent is Parent);
		Sys.println("Parent" is Parent);
		Sys.println(startup);
		Sys.println(value.same);
		Sys.println(check(value));
		Sys.println(effect() is Root);
		final clazz = Parent;
		Sys.println(clazz == Parent);
		Sys.println(value.classify());
		final probe = () -> (value is Root);
		Sys.println(probe());
		Sys.println(Outcome.Done is Parent);
		Sys.println(selected == Parent);
	}
}

/** A real superclass provides the positive inherited-membership case. */
class Parent implements Branch {
	public function new() {}
}

/** The value is a child instance, not a copied parent allocation. */
class Child extends Parent {
	public var same:Bool = new Parent() is Root;

	public function classify():Bool
		return this is Branch;
}

/** An unrelated class supplies the negative runtime check. */
class Other {}

/** Membership must include a superclass's transitive interfaces. */
interface Root {}

interface Branch extends Root {}
interface Unrelated {}

/** An enum value cannot acquire nominal class membership. */
enum Outcome {
	Done;
}
