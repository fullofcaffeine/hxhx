/** Exercise ordinary nested patterns without any macro runtime dependency. */
class Main {
	static function arrayMatch(value:Array<Int>):String {
		return switch value {
			case [1, 2]: "array";
			case _: "other";
		};
	}

	static function objectMatch(value:{name:String}):String {
		return switch value {
			case {name: "yes"}: "object";
			case _: "other";
		};
	}

	static function nestedArrayMatch(value:Array<Array<Int>>):String {
		return switch value {
			case [[1], [2]]: "nested";
			case _: "other";
		};
	}

	static function captureArray(value:Array<Int>):Int {
		return switch value {
			case [_, result]: result;
			case _: -1;
		};
	}

	static function arrayStatement(value:Array<Int>):Void {
		switch value {
			case [1, 2]:
				Sys.println("statement");
			case _:
				Sys.println("other");
		}
	}

	static function alternative(value:Array<Int>):Int {
		return switch value {
			case [0, result] | [result, 0]: result;
			case _: -1;
		};
	}

	static function nested(v:Array<Array<Int>>):Int
		return switch v {
			case [[0, x] | [x, 0]]: x;
			case _: -1;
		};

	static function object(v:{a:Int, b:Int}):Int
		return switch v {
			case {a: 0, b: x}
				| {a: x, b: 0}: x;
			case _: -1;
		};

	static function capture(v:Array<Array<Int>>):Int
		return switch v {
			case [all = [0, x]] | [all = [x, 0]]: all[0] + x;
			case _: -1;
		};

	static function statement(v:Array<Int>):Void
		switch v {
			case [0, x] | [x, 0]:
				Sys.println(x);
			case _:
				Sys.println(-1);
		}

	static function booleanField(value:{flag:Bool}):String {
		return switch value {
			case {flag: flag}: flag ? "yes" : "no";
		};
	}

	static function booleanArray(value:Array<Bool>):String {
		return switch value {
			case [flag]: flag ? "yes" : "no";
			case _: "other";
		};
	}

	static function booleanRoot(value:Bool):String {
		return switch value {
			case flag: flag ? "yes" : "no";
		};
	}

	static function main():Void {
		Sys.println(booleanRoot(true));
		Sys.println(booleanRoot(false));
		Sys.println(booleanField({flag: true}));
		Sys.println(booleanField({flag: false}));
		Sys.println(booleanArray([true]));
		Sys.println(booleanArray([false]));
		Sys.println(nested([[0, 7]]));
		Sys.println(nested([[7, 0]]));
		Sys.println(nested([[3, 4]]));
		Sys.println(object({a: 0, b: 7}));
		Sys.println(object({a: 7, b: 0}));
		Sys.println(object({a: 3, b: 4}));
		Sys.println(capture([[0, 7]]));
		Sys.println(capture([[7, 0]]));
		Sys.println(capture([[3, 4]]));
		statement([0, 7]);
		statement([7, 0]);
		statement([3, 4]);
		Sys.println(alternative([0, 7]));
		Sys.println(alternative([7, 0]));
		Sys.println(alternative([3, 4]));
		Sys.println(arrayMatch([1, 2]));
		Sys.println(arrayMatch([1, 3]));
		Sys.println(arrayMatch([1]));
		Sys.println(arrayMatch([1, 2, 3]));
		try {
			arrayMatch(null);
			Sys.println("no-null-failure");
		} catch (error:Dynamic) {
			Sys.println("null-access");
		}
		Sys.println(nestedArrayMatch([[1], [2]]));
		Sys.println(nestedArrayMatch([[1], [3]]));
		Sys.println(nestedArrayMatch([[1, 2], [2]]));
		Sys.println(captureArray([3, 7]));
		arrayStatement([1, 2]);
		arrayStatement([2, 1]);
		Sys.println(objectMatch({name: "yes"}));
		Sys.println(objectMatch({name: "no"}));
	}
}
