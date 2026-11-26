/**
	A direct match outranks a cast conversion: upstream's rate_conv adds one per abstract
	conversion (src/codegen/overloads.ml). The overloads return different types, so the
	assignments only type when the right overload is selected.
**/
extern class Picker {
	overload static function pick(s:String):String;
	overload static function pick(length:Length):Int;
}

class OverloadPick {
	static function main() {
		final direct:String = Picker.pick("abc");
		final converted:Int = Picker.pick(new Length(2));
	}
}
