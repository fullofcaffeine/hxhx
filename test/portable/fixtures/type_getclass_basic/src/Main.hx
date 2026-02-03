package;

interface IFoo {}

class Base {
	public function new() {}
}

class Child extends Base implements IFoo {
	public function new() {
		super();
	}
}

class Main {
	static function main() {
		final b:Base = new Child();
		final i:IFoo = new Child();
		final d:Dynamic = new Child();
		final anon:Dynamic = { a: 1 };

		Sys.println("base=" + Type.getClassName(Type.getClass(b)).split(".").pop());
		Sys.println("iface=" + Type.getClassName(Type.getClass(i)).split(".").pop());
		Sys.println("dyn=" + Type.getClassName(Type.getClass(d)).split(".").pop());
		Sys.println("anon=" + (Type.getClass(anon) == null));
	}
}

