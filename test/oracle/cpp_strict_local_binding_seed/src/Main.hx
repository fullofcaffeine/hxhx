/** Exercises closure ownership and C++ spelling collisions after local projection. */
class Main {
	static function combine(first:Int, second:Int):Int
		return first + second;

	static function keywordParameters(first:Int, int:Int, int_:Int):Int
		return first + int * 10 + int_;

	/** Compiler-created storage must leave same-spelled captured source locals intact. */
	static function helperCollision():Void {
		if (!BindingTypeProbe.isOfType(null, 1))
			throw "polymorphic helper parameters lost their distinct bindings";
		var absentNumber:Null<Int> = null;
		var absentCallback:Void->Int = null;
		var absentObject:BindingTypeProbe = null;
		final numberIsNull = BindingTypeProbe.isOfType(absentNumber, 0);
		final callbackIsNull = BindingTypeProbe.isOfType(absentCallback, false);
		final objectIsNull = BindingTypeProbe.isOfType(absentObject, "");
		if (!numberIsNull)
			throw "erased generic integer argument lost its null carrier";
		if (!callbackIsNull)
			throw "erased generic callback argument lost its null carrier";
		if (!objectIsNull)
			throw "erased generic object argument lost its null carrier";
		var __hxhx_comp_out = 10;
		var values = [for (i in [1, 2]) __hxhx_comp_out + i];
		if (values[0] != 11 || values[1] != 12 || __hxhx_comp_out != 10)
			throw "comprehension helper captured the wrong storage";
		var second = 10;
		var bound = combine.bind(second);
		if (bound(3) != 13)
			throw "bound method parameter shadowed its captured argument";
		var keywords = keywordParameters.bind(1);
		if (keywords(2, 3) != 24)
			throw "bound method parameters lost their distinct slots";
		var __hxhx_range_out = 3;
		var range = __hxhx_range_out...(__hxhx_range_out + 2);
		var total = 0;
		for (value in range)
			total += value;
		if (total != 7)
			throw "range storage shadowed its captured endpoint";
	}

	/** Loop storage must not borrow a differently typed local with a neighboring name. */
	static function loopCollision():Void {
		var int_:String = "word";
		for (int in [1, 2]) {
			if (Std.string(int + 1) != (int == 1 ? "2" : "3"))
				throw "loop integer binding changed";
			if (int_.toUpperCase() != "WORD")
				throw "loop captured string binding changed";
		}
		if (int_.toUpperCase() != "WORD")
			throw "loop scope changed its outer binding";
	}

	/** Each operation requires the representation of its own binding. */
	static function typedCollision(int:Int):Void {
		var int_:String = "word";
		var int__2:Bool = true;
		Sys.println(int + 5);
		Sys.println(int_.toUpperCase());
		Sys.println(int__2 ? "suffix" : "wrong");
	}

	static function main():Void {
		helperCollision();
		loopCollision();
		var foo_1 = 100;
		var foo = function(value:Int):Int return value + 1;
		var first = foo.bind(10);
		var foo = function(?value:Int):Int return value == null ? 20 : value;
		var second = foo.bind(_);
		var foo = function(value:Int):Int return value + 3;
		var third = foo.bind(30);
		var int = 7;
		var int_ = 9;
		Sys.println(first());
		Sys.println(second());
		Sys.println(third());
		Sys.println(foo_1);
		Sys.println(int);
		Sys.println(int_);
		typedCollision(7);
	}
}

/** The specialized helper still owns an ordinary authored function body. */
class BindingTypeProbe {
	public static function isOfType(int:Dynamic, int_:Dynamic):Bool
		return int == null && int_ != null;
}
