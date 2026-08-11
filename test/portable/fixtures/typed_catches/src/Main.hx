class Base {
	public final label:String;

	public function new(label:String) {
		this.label = label;
	}
}

class Child extends Base {
	public final detail:Int;

	public function new(label:String, detail:Int) {
		super(label);
		this.detail = detail;
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
			throw new Child("child", 7);
		} catch (e:Child) {
			parts.push("child=" + e.label + "/" + e.detail);
		} catch (e:Base) {
			parts.push("base");
		}

		try {
			throw new Base("base");
		} catch (e:Child) {
			parts.push("child2");
		} catch (e:Base) {
			parts.push("base2=" + e.label);
		}

		// RTTI-based typed catches:
		// - thrown as Base, but runtime is Child -> should match catch(Child).
		// - thrown as Dynamic, but runtime is Child -> should match catch(Base).
		try {
			final b:Base = new Child("child", 7);
			throw b;
		} catch (e:Child) {
			parts.push("child3=" + e.label + "/" + e.detail);
		} catch (e:Base) {
			parts.push("base3");
		}

		try {
			final d:Dynamic = new Child("child", 7);
			throw d;
		} catch (e:Base) {
			parts.push("base4=" + e.label);
		} catch (e:Dynamic) {
			parts.push("dyn4");
		}

		Sys.println(parts.join(","));
	}
}
