class Base {
	public function new() {}
}

class Child extends Base {
	public function new() {
		super();
	}
}

class Main {
	static function main() {
		final parts:Array<String> = [];

		try {
			throw 0;
		} catch (e:Bool) {
			parts.push("bool");
		} catch (e:Int) {
			parts.push("int=" + e);
		}

		try {
			throw true;
		} catch (e:Int) {
			parts.push("int");
		} catch (e:Bool) {
			parts.push("bool=" + e);
		}

		try {
			throw new Child();
		} catch (e:Child) {
			parts.push("child");
		} catch (e:Base) {
			parts.push("base");
		}

		try {
			throw new Base();
		} catch (e:Child) {
			parts.push("child2");
		} catch (e:Base) {
			parts.push("base2");
		}

		// RTTI-based typed catches:
		// - thrown as Base, but runtime is Child -> should match catch(Child).
		// - thrown as Dynamic, but runtime is Child -> should match catch(Base).
		try {
			final b:Base = new Child();
			throw b;
		} catch (e:Child) {
			parts.push("child3");
		} catch (e:Base) {
			parts.push("base3");
		}

		try {
			final d:Dynamic = new Child();
			throw d;
		} catch (e:Base) {
			parts.push("base4");
		} catch (e:Dynamic) {
			parts.push("dyn4");
		}

		Sys.println(parts.join(","));
	}
}
