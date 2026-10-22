/** Transparent aliases retain the same array and element storage contracts. */
typedef Ints = Array<Int>;
typedef Element = Int;
typedef Elements<T> = Array<T>;
typedef MaybeInts = Null<Array<Int>>;
typedef Box = {var count:Int; var flag:Bool;}

enum Token {
	Item(value:Int);
}

/** Array payloads keep their existing mutable object rather than copying elements. */
enum Packet {
	Values(items:Array<Int>);
	Aliased(items:Ints);
	ElementAlias(items:Array<Element>);
	AppliedAlias(items:Elements<Int>);
	Bools(items:Array<Bool>);
	Texts(items:Array<String>);
	Floats(items:Array<Float>);
	Nested(items:Array<Array<Int>>);
	Records(items:Array<Box>);
	Tokens(items:Array<Token>);
	NullableElements(items:Array<Null<Int>>);
	Pair(left:Array<Int>, right:Array<Int>);
	Optional(?items:Array<Int>);
	Nullable(items:Null<Array<Int>>);
	NullableAlias(items:MaybeInts);

	/** Exercise the explicit Dynamic element boundary, not a typed-element conversion. */
	DynamicElements(items:Array<Dynamic>);
}

/** Observe typed payload identity, storage, nulls, and left-to-right evaluation. */
class Main {
	static function make(label:String, value:Int):Array<Int> {
		Sys.println(label);
		return [value];
	}

	static function item(label:String, value:Int):Int {
		Sys.println(label);
		return value;
	}

	static function main():Void {
		final values = [7, 8];
		final packet = Values(values);
		values[0] = 9;
		values.push(10);
		final equalContents = [9, 8, 10];
		switch packet {
			case Values(stored):
				Sys.println(stored[0]);
				stored[0] = 10;
				Sys.println(equalContents[0]);
				Sys.println(stored[0]);
				Sys.println(stored.length);
				stored[1] = 11;
			case _:
				throw "wrong values constructor";
		}
		Sys.println(values[1]);
		final alias:Ints = values;
		for (value in [Aliased(alias), ElementAlias(values), AppliedAlias(values)])
			switch value {
				case Aliased(stored), ElementAlias(stored), AppliedAlias(stored):
					stored[0] = stored[0] + 1;
					Sys.println(values[0]);
				case _:
					throw "wrong alias constructor";
			}
		final flags = [true, false];
		final bools = Bools(flags);
		flags[0] = false;
		switch bools {
			case Bools(stored):
				Sys.println(stored.length);
				Sys.println(stored[0]);
				Sys.println(stored[1]);
				stored[1] = true;
			case _:
				throw "wrong Boolean constructor";
		}
		Sys.println(flags[1]);
		final words = ["a"];
		switch Texts(words) {
			case Texts(stored):
				Sys.println(stored[0]);
				stored.push("b");
			case _:
				throw "wrong string constructor";
		}
		Sys.println(words.length);
		Sys.println(words[1]);
		switch Floats([1.5]) {
			case Floats(stored):
				Sys.println(stored[0]);
			case _:
				throw "wrong float-array constructor";
		}
		final inner = [2];
		final nested = Nested([inner]);
		inner[0] = 3;
		switch nested {
			case Nested(stored):
				Sys.println(stored[0][0]);
				stored[0][0] = 4;
			case _:
				throw "wrong nested constructor";
		}
		Sys.println(inner[0]);
		final box:Box = {count: 5, flag: true};
		final records = Records([box]);
		box.count = 6;
		switch records {
			case Records(stored):
				Sys.println(stored[0] == box);
				Sys.println(stored[0].count);
				Sys.println(stored[0].flag);
				stored[0].flag = false;
			case _:
				throw "wrong record-array constructor";
		}
		Sys.println(box.flag);
		final tokens = [Item(5)];
		switch Tokens(tokens) {
			case Tokens(stored):
				Sys.println(stored.length);
				switch stored[0] {
					case Item(value): Sys.println(value);
				}
			case _:
				throw "wrong enum-array constructor";
		}
		final nullableElements:Array<Null<Int>> = [null, 5];
		switch NullableElements(nullableElements) {
			case NullableElements(stored):
				Sys.println(stored[0] == null);
				stored[1] = null;
			case _:
				throw "wrong nullable-element constructor";
		}
		Sys.println(nullableElements[1] == null);
		switch Pair(make("left", 1), make("right", 2)) {
			case Pair(left, right):
				Sys.println(left[0]);
				Sys.println(right[0]);
			case _:
				throw "wrong pair constructor";
		}
		switch Values([item("first", 3), item("second", 4)]) {
			case Values(stored):
				Sys.println(stored[0]);
				Sys.println(stored[1]);
			case _:
				throw "wrong literal constructor";
		}
		switch Values([]) {
			case Values(stored):
				Sys.println(stored.length);
			case _:
				throw "wrong empty constructor";
		}
		for (value in [Optional(), Optional(null), Nullable(null), Values(null), NullableAlias(null)])
			switch value {
				case Optional(stored), Nullable(stored), Values(stored), NullableAlias(stored):
					Sys.println(stored == null);
				case _:
					throw "wrong null constructor";
			}
		for (value in [Optional(values), Nullable(values), NullableAlias(values)])
			switch value {
				case Optional(stored), Nullable(stored), NullableAlias(stored):
					stored[0] = stored[0] + 1;
					Sys.println(values[0]);
				case _:
					throw "wrong present constructor";
			}
		// The precise Array<Dynamic> contract deliberately permits heterogeneous values.
		// Keeping this same object must preserve the runtime's distinct Boolean box.
		final heterogeneous:Array<Dynamic> = [true, 5];
		switch DynamicElements(heterogeneous) {
			case DynamicElements(stored):
				Sys.println(stored[0]);
				Sys.println(stored[1]);
				stored[1] = false;
			case _:
				throw "wrong Dynamic-element constructor";
		}
		Sys.println(heterogeneous[1]);
	}
}
