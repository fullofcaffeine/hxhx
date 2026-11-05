import haxe.Int32;
import haxe.Int64;

/** A user class whose fields are also named `high` and `low`; it must keep ordinary field storage. */
class Words {
	public var high:Int;
	public var low:Int;

	public function new(high:Int, low:Int) {
		this.high = high;
		this.low = low;
	}
}

class Main {
	static function next():Int64 {
		Sys.print("receiver ");
		return Int64.make(0, 1);
	}

	static function value():Int {
		Sys.print("value ");
		return 7;
	}

	static function main():Void {
		final max:Int32 = 2147483647;
		final min:Int32 = -2147483648;
		final seven:Int32 = 7;
		final three:Int32 = 3;
		final big:Int32 = 123456789;
		final plain:Int = 5;
		Sys.println("add " + (max + 1) + " " + (max + seven) + " " + (seven + plain) + " " + (plain + seven));
		Sys.println("sub " + (min - 1) + " " + (seven - three) + " " + (seven - plain) + " " + (plain - seven));
		Sys.println("mul " + (max * 2) + " " + (big * big) + " " + (seven * three) + " " + (seven * plain));
		final two:Int32 = 2;
		final four:Int32 = 4;
		Sys.println("div " + (seven / two) + " " + (seven / four) + " " + (plain / two) + " " + (seven / plain));
		Sys.println("mod " + (seven % three) + " " + (seven % plain) + " " + (plain % three) + " " + (min % seven));
		Sys.println("neg " + (-min) + " " + (-seven));
		Sys.println("shl " + (seven << 29) + " " + (max << 1) + " " + (seven << three));
		Sys.println("shr " + (min >> 4) + " " + (min >>> 4) + " " + (seven >> 1));
		Sys.println("bits " + (seven & three) + " " + (seven | 8) + " " + (seven ^ three) + " " + (~seven));
		Sys.println("cmp " + (seven < three) + " " + (seven > three) + " " + (seven <= 7) + " " + (seven >= plain) + " " + (seven == 7) + " "
			+ (seven != three) + " " + (min < max));
		final asInt:Int = max + 1;
		Sys.println("toInt " + asInt + " " + Int32.ucompare(min, max));
		var counter:Int32 = max;
		counter++;
		Sys.println("inc " + counter);
		final before = counter--;
		Sys.println("dec " + before + " " + counter + " " + (--counter) + " " + (++counter));

		final five = Int64.make(0, 5);
		final huge = Int64.make(0x7fffffff, 0xffffffff);
		Sys.println("i64 make " + Int64.toStr(five) + " " + Int64.toStr(huge) + " " + Int64.toStr(Int64.make(1, 0)));
		Sys.println("i64 add " + Int64.toStr(five + 7) + " " + Int64.toStr(huge + 1) + " " + Int64.toStr(five + five));
		Sys.println("i64 sub " + Int64.toStr(five - 7) + " " + Int64.toStr(Int64.make(0x80000000, 0) - 1));
		Sys.println("i64 mul "
			+ Int64.toStr(five * 3)
			+ " "
			+ Int64.toStr(Int64.ofInt(2147483647) * Int64.ofInt(2147483647))
			+ " "
			+ Int64.toStr(huge * 2));
		Sys.println("i64 div " + Int64.toStr(Int64.ofInt(100) / Int64.ofInt(7)) + " " + Int64.toStr(Int64.ofInt(-100) / 7) + " "
			+ Int64.toStr(Int64.ofInt(100) % 7));
		Sys.println("i64 cmp " + Int64.compare(five, huge) + " " + Int64.compare(huge, five) + " " + Int64.compare(five, Int64.ofInt(5)) + " "
			+ (five < huge) + " " + (five == Int64.ofInt(5)));
		Sys.println("i64 conv " + Int64.toInt(Int64.ofInt(-42)) + " " + Int64.toStr(Int64.ofInt(-42)) + " " + five.high + " " + five.low);
		Sys.println("i64 str " + huge + " " + Std.string(five) + " " + Int64.ucompare(Int64.ofInt(-1), five));
		var steps = Int64.ofInt(9);
		final alias = steps;
		steps++;
		Sys.println("i64 inc " + Int64.toStr(steps) + " " + Int64.toStr(alias) + " " + Int64.toStr(steps++) + " " + Int64.toStr(steps--) + " "
			+ Int64.toStr(steps));
		var edge = Int64.make(0, 0xffffffff);
		edge++;
		Sys.println("i64 carry " + Int64.toStr(edge) + " " + edge.high + " " + edge.low);
		final word = @:privateAccess next().set_low(value());
		Sys.println("set " + word);

		var text = "text ";
		text += (max + 1);
		Sys.println(text);
		final words = new Words(1, 2);
		words.low = words.low + words.high;
		words.high++;
		Sys.println("words " + words.high + " " + words.low);

		// Assignments used as values: an Int stored in a Float local is widened.
		var ratio:Float = 0.5;
		ratio = 3;
		final afterStatement = ratio + 0.25;
		final afterValue = (ratio = 5) + 0.25;
		Sys.println("float " + afterStatement + " " + afterValue);
		var total = 0;
		final shown = "total " + (total = 9);
		Sys.println(shown);
		Sys.println("total after " + total);
	}
}
