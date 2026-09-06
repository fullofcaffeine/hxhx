import Type.ValueType;

enum SampleKind {
	Ready;
	Payload(value:Int);
}

class SampleBox {
	public function new() {}
}

/** Exercises each input strategy and observable result of `Type.typeof`. */
class Main {
	static var effectCount = 0;

	static function effectfulBool():Bool {
		effectCount += 1;
		return true;
	}

	static function kindName(kind:ValueType):String {
		return switch (kind) {
			case TNull: "null";
			case TInt: "int";
			case TFloat: "float";
			case TBool: "bool";
			case TObject: "object";
			case TFunction: "function";
			case TClass(_): "class";
			case TEnum(_): "enum";
			case TUnknown: "unknown";
		};
	}

	static function main():Void {
		final dynamicInt:Dynamic = 7;
		final nullableIntNull:Null<Int> = null;
		final nullableIntValue:Null<Int> = 8;
		final nullableInt32Value:Null<haxe.Int32> = 9;
		final floatValue:Float = 2.5;
		final enumValue:SampleKind = SampleKind.Ready;
		final nullableEnumNull:Null<SampleKind> = null;
		final nullableEnumValue:Null<SampleKind> = SampleKind.Payload(3);
		final classValue = new SampleBox();
		final stringValue = "text";
		final functionValue = () -> 1;

		Sys.println('dynamic-int=${kindName(Type.typeof(dynamicInt))}');
		Sys.println('nullable-int-null=${kindName(Type.typeof(nullableIntNull))}');
		Sys.println('nullable-int-value=${kindName(Type.typeof(nullableIntValue))}');
		Sys.println('nullable-int32-value=${kindName(Type.typeof(nullableInt32Value))}');
		Sys.println('bool=${kindName(Type.typeof(effectfulBool()))} effects=$effectCount');
		Sys.println('float=${kindName(Type.typeof(floatValue))}');
		Sys.println('enum=${kindName(Type.typeof(enumValue))}');
		Sys.println('nullable-enum-null=${kindName(Type.typeof(nullableEnumNull))}');
		Sys.println('nullable-enum-value=${kindName(Type.typeof(nullableEnumValue))}');
		Sys.println('class=${kindName(Type.typeof(classValue))}');
		Sys.println('string=${kindName(Type.typeof(stringValue))}');
		Sys.println('function=${kindName(Type.typeof(functionValue))}');
	}
}
