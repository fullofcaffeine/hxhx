class Main {
	static function unusedDepth(message:String, depth:Int = 0):String {
		return message;
	}

	static function unusedPretty(value:Int, pretty:Bool = false):Int {
		return value;
	}

	static function usedDepth(depth:Int = 0):Int {
		return depth + 1;
	}

	static function usedPretty(pretty:Bool = false):Bool {
		return pretty;
	}

	static function main() {
		Sys.println("unused_depth=" + unusedDepth("kept"));
		Sys.println("unused_pretty=" + unusedPretty(7));
		Sys.println("used_depth_default=" + usedDepth());
		Sys.println("used_depth_value=" + usedDepth(4));
		Sys.println("used_pretty_default=" + usedPretty());
		Sys.println("used_pretty_value=" + usedPretty(true));
	}
}
