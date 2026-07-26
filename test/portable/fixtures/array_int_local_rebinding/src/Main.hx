/**
	Proves that replacing an array local and mutating the referenced array remain
	distinct operations across straight-line, nested, and captured storage.
**/
class Main {
	static function straightLine():String {
		var step = 0;
		final arrayAt = function(expectedStep:Int, nextStep:Int, value:Int):Array<Int> {
			if (step != expectedStep)
				return [-100];
			step = nextStep;
			return [value];
		};
		var values:Array<Int> = arrayAt(0, 1, 1);
		values = arrayAt(1, 2, 2);
		return values[0] + "/" + step;
	}

	static function nestedBlock():String {
		var step = 0;
		final arrayAt = function(expectedStep:Int, nextStep:Int, value:Int):Array<Int> {
			if (step != expectedStep)
				return [-100];
			step = nextStep;
			return [value];
		};
		var values:Array<Int> = arrayAt(0, 1, 1);
		final alias = values;
		{
			values[0] = 2;
			values = arrayAt(1, 2, 3);
		}
		return alias[0] + "/" + values[0] + "/" + step;
	}

	static function captured():String {
		var step = 0;
		final arrayAt = function(expectedStep:Int, nextStep:Int, value:Int):Array<Int> {
			if (step != expectedStep)
				return [-100];
			step = nextStep;
			return [value];
		};
		var values:Array<Int> = arrayAt(0, 1, 1);
		final alias = values;
		final replace = function() {
			if (step != 1)
				return;
			step = 2;
			values = arrayAt(2, 3, 4);
		};
		replace();
		return alias[0] + "/" + values[0] + "/" + step;
	}

	static function main():Void {
		final output = straightLine() + "|" + nestedBlock() + "|" + captured();
		#if js
		js.Syntax.code("console.log({0})", output);
		#else
		Sys.println(output);
		#end
	}
}
