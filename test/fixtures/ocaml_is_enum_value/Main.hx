/** Both constant and payload enum constructors must keep runtime enum identity. */
enum Choice {
	First;
	Value(value:Int);
}

/** Exercise the standard Dynamic reflection boundary with unrelated value kinds. */
class Main {
	static function producer():Choice {
		Sys.println("producer");
		return Choice.Value(3);
	}

	static function callback():Void {}

	static function main():Void {
		Sys.println(Reflect.isEnumValue(Choice.First));
		Sys.println(Reflect.isEnumValue(Choice.Value(3)));
		Sys.println(Reflect.isEnumValue(producer()));
		Sys.println(Reflect.isEnumValue(null));
		Sys.println(Reflect.isEnumValue(0));
		Sys.println(Reflect.isEnumValue(true));
		Sys.println(Reflect.isEnumValue("First"));
		Sys.println(Reflect.isEnumValue({value: 3}));
		Sys.println(Reflect.isEnumValue([1, 2]));
		Sys.println(Reflect.isEnumValue(callback));
		Sys.println(Reflect.isEnumValue(Type.getEnum(Choice.First)));
	}
}
