/** Runtime identity must survive a Dynamic throw and a broader catch binding. */
class Main {
	static function main():Void {
		var value:Dynamic = new Child();
		try {
			try {
				throw value;
			} catch (error:Other) {
				Sys.println("wrong type");
			} catch (error:Base) {
				Sys.println("base");
				throw error;
			}
		} catch (error:Child) {
			Sys.println("child");
		} catch (error:Dynamic) {
			Sys.println("wrong dynamic");
		}
	}
}

class Base {
	public function new() {}
}

class Child extends Base {
	public function new() {
		super();
	}
}

class Other {
	public function new() {}
}
