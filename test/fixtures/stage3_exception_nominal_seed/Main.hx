import Main.Child as RenamedChild;

/** Runtime identity must survive a Dynamic throw and a broader catch binding. */
class Main {
	static function main():Void {
		var child = new Child();
		var value:Dynamic = child;
		try {
			try {
				throw value;
			} catch (error:Other) {
				Sys.println("wrong type");
			} catch (error:Base) {
				if (error.baseValue != 8 || error != child)
					throw "lost constructed base value or identity";
				Sys.println("base");
				throw error;
			}
		} catch (error:Child) {
			if (error.childValue != 11 || error != child)
				throw "lost initialized child value or identity";
			Sys.println("child");
		} catch (error:Dynamic) {
			Sys.println("wrong dynamic");
		}
		try {
			throw child;
		} catch (error:RenamedChild) {
			Sys.println("alias");
		}
		try {
			throw value;
		} catch (error:AncestorMarker) {
			Sys.println("interface");
		}
	}
}

interface AncestorMarker {}
interface Marker extends AncestorMarker {}

class Base implements Marker {
	public var baseValue:Int = 3;

	public function new() {
		baseValue = 8;
	}
}

class Child extends Base {
	public var childValue:Int = 11;

	public function new() {
		super();
	}
}

class Other {
	public function new() {}
}
