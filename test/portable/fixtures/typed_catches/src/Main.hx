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

		Sys.println(parts.join(","));
	}
}
