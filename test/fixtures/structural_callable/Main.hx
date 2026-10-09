typedef Reader = {
	function choose(?label:String, value:Int):Int;
}

class Main {
	static var receiverCalls:Int = 0;

	static function provide(reader:Reader):Reader {
		receiverCalls++;
		return reader;
	}

	static function choose(?label:String, value:Int):Int {
		if (label != null)
			throw "optional argument was not skipped";
		return value;
	}

	static function run(reader:Reader):Void {
		Sys.println(reader.choose(7));
		Sys.println(provide(reader).choose(8));
	}

	static function main():Void {
		var reader:Reader = {choose: choose};
		run(reader);
		Sys.println(receiverCalls);
	}
}
