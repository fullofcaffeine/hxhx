package;

import a.b.Foo;

class Main {
	static function main() {
		Sys.println("fooName=" + Type.getClassName(Foo));
		Sys.println("fooResolved=" + (Type.resolveClass("a.b.Foo") == Foo));
		Sys.println("missing=" + (Type.resolveClass("nope.Nope") == null));
	}
}

