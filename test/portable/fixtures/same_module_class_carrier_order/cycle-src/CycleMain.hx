class LeftValue {
	public final right:RightValue;

	public function new(right:RightValue) {
		this.right = right;
	}
}

class RightValue {
	public var left:Null<LeftValue>;

	public function new() {
		left = null;
	}
}

class CycleMain {
	static function main() {}
}
