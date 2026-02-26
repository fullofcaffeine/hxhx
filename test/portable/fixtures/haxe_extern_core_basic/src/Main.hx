import haxe.extern.AsVar;
import haxe.extern.EitherType;
import haxe.extern.Rest;

class Main {
	static function addOne(value:AsVar<Int>):Int {
		return value + 1;
	}

	static function sumWithRest(prefix:Int, rest:Rest<Int>):Int {
		var sum = prefix;
		for (value in rest) {
			sum += value;
		}
		return sum;
	}

	static function main() {
		Sys.println("asVar=" + addOne(41));
		final eitherInt:EitherType<Int, String> = 10;
		final eitherString:EitherType<Int, String> = "hx";
		if (eitherInt != null && eitherString != null) {
			Sys.println("either=typed");
		}
		Sys.println("rest=" + sumWithRest(1, 2, 3, 4));
	}
}
