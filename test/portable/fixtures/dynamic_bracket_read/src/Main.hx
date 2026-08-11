class Main {
	static final staticValues:Dynamic = [3, 4];
	static final staticValue:Dynamic = staticValues[0];
	static var receiverCalls = 0;
	static var indexCalls = 0;

	static function receiver():Array<Int> {
		receiverCalls++;
		return [10, 20, 30];
	}

	static function index():Int {
		indexCalls++;
		return 1;
	}

	static function main() {
		final dynamicReceiver:Dynamic = receiver();
		final value:Dynamic = dynamicReceiver[index()];
		Sys.println("value=" + value);
		Sys.println("receiver_calls=" + receiverCalls);
		Sys.println("index_calls=" + indexCalls);
		Sys.println("static_value=" + staticValue);
	}
}
