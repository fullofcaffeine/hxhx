/** Runtime enum values and enum handles must keep separate representations. */
enum ReflectionChoice {
	Empty;
	Item(value:Int);
}

/** An ordinary class supplies an instance identity and a public lookup name. */
class ReflectionBox {
	public function new() {}
}

/** Public reflection observes values without copying them or repeating argument effects. */
class Main {
	static var calls:Int = 0;

	static function makeChoice():ReflectionChoice {
		calls++;
		return ReflectionChoice.Item(7);
	}

	static function main():Void {
		final box = new ReflectionBox();
		Sys.println("string=" + Type.getClassName(Type.getClass("sample")));
		Sys.println("array=" + Type.getClassName(Type.getClass([1])));
		Sys.println("null-class=" + Type.getClassName(null));
		Sys.println("null-enum=" + Type.getEnumName(null));
		Sys.println("integer=" + (Type.getClass(1) == null));
		Sys.println("record=" + (Type.getClass({value: 1}) == null));
		Sys.println("enum-instance=" + (Type.getClass(ReflectionChoice.Empty) == null));
		Sys.println("class-handle=" + (Type.getClass(ReflectionBox) == null));
		Sys.println("enum-handle=" + (Type.getClass(ReflectionChoice) == null));
		Sys.println("instance=" + (Type.getClass(box) == ReflectionBox));
		Sys.println("resolved-instance=" + Std.isOfType(box, Type.resolveClass("ReflectionBox")));
		Sys.println("enum=" + Type.getEnumName(ReflectionChoice));
		Sys.println("enum-identity=" + (Type.getEnum(ReflectionChoice.Empty) == ReflectionChoice));
		Sys.println("resolved-enum=" + (Type.resolveEnum("ReflectionChoice") == ReflectionChoice));
		Sys.println("missing-class=" + (Type.resolveClass("MissingReflectionType") == null));
		Sys.println("missing-enum=" + (Type.resolveEnum("MissingReflectionType") == null));
		Sys.println("class-as-enum=" + (Type.resolveEnum("ReflectionBox") == null));
		Sys.println("effect-enum=" + Type.getEnumName(Type.getEnum(makeChoice())));
		Sys.println("calls=" + calls);
		final classCategory = Type.ValueType.TClass(ReflectionBox);
		final enumCategory = Type.ValueType.TEnum(ReflectionChoice);
		Sys.println("class-payload=" + Type.getEnumName(Type.getEnum(classCategory)));
		Sys.println("enum-payload=" + Type.getEnumName(Type.getEnum(enumCategory)));
	}
}
