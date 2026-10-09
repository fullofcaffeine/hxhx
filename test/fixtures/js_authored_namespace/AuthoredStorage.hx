/** Namespace placement cannot replace this class's constructor or instance behavior. */
class AuthoredStorage {
	public static var events:String = "";

	var value:Int;

	public function new(value:Int) {
		events += "construct;";
		this.value = value;
	}

	public function read():Int {
		events += "read;";
		return value;
	}

	static function main():Void {
		final value:AuthoredStorage = new InheritedStorage(7);
		if (value.read() != 8 || events != "construct;read;")
			throw "authored construction and inherited dispatch";
		final callback = value.read;
		if (callback() != 8 || events != "construct;read;read;")
			throw "captured authored method";
	}
}

class InheritedStorage extends AuthoredStorage {
	public override function read():Int
		return super.read() + 1;
}
