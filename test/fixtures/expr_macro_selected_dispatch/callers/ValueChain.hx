package callers;

class ValueChain {
	public static var instance:ValueChain = new ValueChain();

	function new() {}

	public function run():Int {
		return 1;
	}

	static function call():Int {
		return ValueChain.instance.run();
	}
}
