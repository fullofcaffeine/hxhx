class Main {
	static function printLine(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	static function nestedLoops():String {
		var outer = 0;
		var result = "";
		while (outer < 3) {
			outer++;
			var inner = 0;
			while (inner < 4) {
				inner++;
				if (inner == 2)
					continue;
				if (inner == 4)
					break;
				result += outer + "" + inner + ";";
			}
			if (outer == 2)
				continue;
			result += "o" + outer + ";";
		}
		return result;
	}

	static function doWhileContinue():String {
		var index = 0;
		var result = "";
		do {
			index++;
			if (index % 2 == 1)
				continue;
			result += index;
		} while (index < 5);
		return result;
	}

	static function throughTry():String {
		var index = 0;
		var result = "";
		while (index < 5) {
			index++;
			try {
				if (index == 2)
					continue;
				if (index == 4)
					break;
				result += index;
			} catch (_:Dynamic) {
				result += "caught";
			}
		}
		return result;
	}

	static function voidLoop(parts:Array<String>):Void {
		var index = 0;
		while (true) {
			index++;
			if (index == 1)
				continue;
			if (index == 3)
				break;
			parts.push("v" + index);
		}
	}

	static function floatLoop():Float {
		var index = 0;
		while (true) {
			index++;
			if (index == 1)
				continue;
			if (index == 3)
				break;
		}
		return index - 0.5;
	}

	static function nestedFunction():String {
		var outer = 0;
		while (true) {
			outer++;
			if (outer == 1)
				continue;
			break;
		}
		final local = function() {
			var inner = 0;
			while (true) {
				inner++;
				if (inner == 1)
					continue;
				break;
			}
			return inner;
		};
		return outer + ":" + local();
	}

	static function main() {
		final parts = [];
		voidLoop(parts);
		printLine("nested=" + nestedLoops() + ",do=" + doWhileContinue() + ",try=" + throughTry() + ",void=" + parts.join("|") + ",float=" + floatLoop()
			+ ",nestedFn=" + nestedFunction());
	}
}
