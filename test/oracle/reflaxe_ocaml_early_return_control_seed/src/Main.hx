class Main {
	static function printLine(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	static function branch(value:Int):Int {
		if (value == 0)
			return 1;
		return 2;
	}

	static function loop(limit:Int):Int {
		var index = 0;
		while (true) {
			if (index == limit)
				return index;
			index += 1;
		}
		return -1;
	}

	static function nestedBlock(value:Int):Int {
		{
			if (value > 0)
				return 4;
		}
		return 5;
	}

	static function throughTry(value:Int):Int {
		try {
			if (value > 0)
				return 7;
		} catch (_:Dynamic) {
			return 99;
		}
		return 3;
	}

	static function nestedClosure():Int {
		final local = function(flag:Bool):Int {
			if (flag)
				return 6;
			return 0;
		};
		if (local(true) == 6)
			return 8;
		return 9;
	}

	static function main() {
		printLine("branch0=" + branch(0));
		printLine("branch1=" + branch(1));
		printLine("loop3=" + loop(3));
		printLine("block1=" + nestedBlock(1));
		printLine("block0=" + nestedBlock(0));
		printLine("try1=" + throughTry(1));
		printLine("try0=" + throughTry(0));
		printLine("closure=" + nestedClosure());
		printLine("OK early_return_control");
	}
}
