/** Observes canonical type values, constructor identity, and interface membership. */
class Main {
	static function main():Void {
		final child = new Child();
		final selected:Class<Parent> = Parent;
		Sys.println(Type.getClass(child) == Child);
		Sys.println(Type.getClassName(Type.getClass(child)));
		Sys.println(selected == child.selected);
		Sys.println(child is Parent);
		Sys.println(child is Root);
		Sys.println(child is Diamond);
		Sys.println(child is Other);
		Sys.println(new Parent() is Child);
		Sys.println(Type.getClassName(Type.getClass("text")));
		Sys.println(Type.getClassName(Type.getClass([])));
		Sys.println(Type.getClass("a") == Type.getClass("b"));
		Sys.println(child.__hxhx_runtime_type);
		final __hxhx_runtime_type = 31;
		final __hxhx_is_of_type = 37;
		final __hxhx_type_get_class = 41;
		Sys.println(child is Parent);
		Sys.println(Type.getClass(child) == Child);
		Sys.println(__hxhx_runtime_type + __hxhx_is_of_type + __hxhx_type_get_class);
	}
}

interface Root {}
interface Left extends Root {}
interface Right extends Root {}
interface Diamond extends Left extends Right {}

/** The most-derived identity must exist before the base constructor executes. */
class Parent implements Diamond {
	public var __hxhx_runtime_type:Int = 23;
	public var selected:Class<Parent> = Parent;

	public function new() {
		Sys.println(Type.getClassName(Type.getClass(this)));
	}
}

class Child extends Parent {}
class Other {}
