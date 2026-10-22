/** Executable input conversions must occur beside their source operand. */
abstract Number(Int) {
	@:from public static function convert(value:Int):Number {
		Main.order += "C";
		if (value == 99)
			throw "conversion stopped";
		return cast value;
	}

	@:op(A / B) public static function general(left:Number, right:Number):String {
		Main.order += "O";
		return "general";
	}

	@:op(A / B) public static function specific(left:Int, right:Number):String
		return "specific";

	@:op(A + B) public static function sum(left:Number, right:Number):Int {
		Main.order += "O";
		return (cast left : Int) + (cast right : Int);
	}

	@:commutative @:op(A * B) public static function reversed(left:Number, right:Word):String {
		Main.order += "O";
		return "reversed";
	}

	@:op(A % B) public static function outputInput(left:Number, right:Int):Int {
		Main.order += "O";
		return right;
	}
}

/** A distinct abstract forces conversion on the source-left argument of a reversed call. */
abstract Word(String) {
	@:from public static function convert(value:String):Word {
		Main.order += "C";
		return cast value;
	}
}

/** Output methods must remain executable when an operator needs a primitive argument. */
abstract OutputNumber(Int) {
	@:to public function number():Int {
		Main.order += "C";
		return this;
	}
}

/** Bodyless operators use the same ordered conversions before their primitive operation. */
abstract NativeNumber(Int) {
	@:from public static function convert(value:Int):NativeNumber {
		Main.order += "C";
		return cast value;
	}

	@:op(A - B) public static function difference(left:NativeNumber, right:NativeNumber):NativeNumber;
}

/** An inline mutating operator converts its argument without losing the receiver place. */
abstract MutableNumber(Int) {
	@:op(A += B) public inline function increase(right:Number):Void {
		this += (cast right : Int);
	}
}

/** Assertions independently specify selection, conversion effects, result writeback, and operand order. */
class Main {
	public static var order:String = "";

	static function left():Int {
		order += "L";
		return 4;
	}

	static function right():Number {
		order += "R";
		return cast 2;
	}

	static function rightInt():Int {
		order += "R";
		return 2;
	}

	static function word():String {
		order += "L";
		return "text";
	}

	static function output():OutputNumber {
		order += "R";
		return cast 2;
	}

	static function bad():Int {
		order += "L";
		return 99;
	}

	static function main():Void {
		if (left() / right() != "general" || order != "LCRO")
			throw "input conversion order";
		order = "";
		if (word() * right() != "reversed" || order != "LCRO")
			throw "reversed conversion order";
		order = "";
		var outputOwner:Number = cast 4;
		if (outputOwner % output() != 2 || order != "RCO")
			throw "output conversion order";
		order = "";
		var stopped = false;
		try {
			bad() / right();
		} catch (error:String) {
			stopped = error == "conversion stopped";
		}
		if (!stopped || order != "LC")
			throw "conversion failure evaluated the next operand";
		order = "";
		var value:Number = cast 4;
		value += rightInt();
		if ((cast value : Int) != 6 || order != "RCOC")
			throw "compound conversion order";
		order = "";
		var nativeValue:NativeNumber = cast 4;
		nativeValue -= rightInt();
		if ((cast nativeValue : Int) != 2 || order != "RC")
			throw "bodyless compound conversion order";
		order = "";
		var mutableValue:MutableNumber = cast 4;
		mutableValue += rightInt();
		if ((cast mutableValue : Int) != 6 || order != "RC")
			throw "inline argument conversion order";
	}
}
