/** Observable exception values and control destinations, shared with upstream Haxe. */
class Main {
	static function choose():String {
		var value = try {
			throw 7;
			"unreachable";
		} catch (error:String) {
			"wrong string";
		} catch (error:Int) {
			"integer:" + error;
		} catch (error:Dynamic) {
			"wrong dynamic";
		};
		return value;
	}

	static function rethrow():String {
		try {
			try {
				throw true;
			} catch (error:Dynamic) {
				throw error;
			}
		} catch (error:Int) {
			return "wrong integer";
		} catch (error:Bool) {
			return "boolean:" + error;
		}
		return "missing throw";
	}

	static function returned():Int {
		try {
			return 19;
		} catch (error:Dynamic) {
			return -1;
		}
	}

	static function loops():Int {
		var total = 0;
		for (index in 0...5) {
			try {
				if (index == 1)
					continue;
				if (index == 3)
					break;
				total += index;
			} catch (error:Dynamic) {
				total += 100;
			}
		}
		return total;
	}

	static function payload():Int {
		Sys.println("payload");
		return 31;
	}

	static function effects():Void {
		try {
			throw payload();
		} catch (error:Int) {
			error += 1;
			Sys.println(error);
		}
		try {
			try {
				throw 37;
			} catch (error:String) {
				Sys.println("wrong handler");
			}
		} catch (error:Int) {
			Sys.println(error);
		}
		try {
			try {
				throw "first";
			} catch (error:String) {
				throw "second";
			} catch (error:Dynamic) {
				Sys.println("wrong sibling");
			}
		} catch (error:String) {
			Sys.println(error);
		}
	}

	static function nestedLoops():Int {
		var total = 0;
		var outer = 0;
		while (outer < 3) {
			outer += 1;
			try {
				var inner = 0;
				do {
					inner += 1;
					try {
						if (inner == 1)
							continue;
						if (inner == 3)
							break;
						total += 1;
					} catch (error:Dynamic) {
						total += 100;
					}
				} while (inner < 5);
				if (outer == 2)
					continue;
				total += 10;
			} catch (error:Dynamic) {
				total += 1000;
			}
		}
		return total;
	}

	static function main():Void {
		Sys.println(choose());
		Sys.println(rethrow());
		Sys.println(returned());
		Sys.println(loops());
		var normal = try {
			23;
		} catch (error:Dynamic) {
			0;
		};
		Sys.println(normal);
		var error = "outer";
		try {
			throw "inner";
		} catch (error:String) {
			Sys.println(error);
		}
		Sys.println(error);
		effects();
		Sys.println(nestedLoops());
		var __hx_thrown_value = "not captured";
		try {
			throw "caught";
		} catch (error:String) {
			Sys.println(__hx_thrown_value);
		}
	}
}
