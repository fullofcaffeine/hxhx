/** Scalar abstract switches use their stored value and evaluate the input once. */
class Main {
	static var reads:Int = 0;

	static function read():Count {
		reads++;
		return 1;
	}

	static function select(value:Count):Int {
		return switch (value) {
			case 0: 10;
			case 1 | 2: 20;
			default: 30;
		};
	}

	static function nullable(value:Null<Count>):Int {
		return switch (value) {
			case null: 40;
			case 0: 10;
			default: 30;
		};
	}

	static function generic(value:Box<Int>):Int {
		return switch (value) {
			case 3: 50;
			default: 60;
		};
	}

	static function text(value:Text):Int {
		return switch (value) {
			case "hit": 70;
			case null: 80;
			default: 90;
		};
	}

	static function flag(value:Flag):Int {
		return switch (value) {
			case true: 100;
			default: 110;
		};
	}

	static function main():Void {
		if (select(read()) != 20 || reads != 1)
			throw "abstract switch changed input evaluation";
		if (select(0) != 10 || select(2) != 20 || select(9) != 30)
			throw "abstract switch selected the wrong arm";
		if (nullable(null) != 40 || nullable(0) != 10 || nullable(9) != 30)
			throw "nullable abstract switch lost null";
		if (generic(3) != 50 || generic(4) != 60)
			throw "generic abstract switch lost its substituted backing type";
		if (text("hit") != 70 || text(null) != 80 || text("miss") != 90)
			throw "String abstract switch selected the wrong arm";
		if (flag(true) != 100 || flag(false) != 110)
			throw "Bool abstract switch selected the wrong arm";
	}
}

/** Pattern matching needs storage identity, not an implicit conversion to Int. */
abstract Count(Int) from Int {}

/** Generic storage is selected from the applied type argument. */
abstract Box<T>(T) from T {}

/** String storage preserves null as a distinct pattern value. */
abstract Text(String) from String {}

/** Boolean patterns compare the existing stored Boolean. */
abstract Flag(Bool) from Bool {}
