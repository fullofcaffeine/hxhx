import Type as Types;

/** A singleton still owns an enum descriptor independent of its integer tag. */
enum Token {
	Mark;
}

/** Runtime descriptors are values, distinct from class instances and enum instances. */
enum Payload {
	ClassValue(value:Class<Dynamic>);
	EnumType(value:Enum<Dynamic>);
	OptionalClass(?value:Class<Dynamic>);
	OptionalEnum(?value:Enum<Dynamic>);
	NullableClass(value:Null<Class<Dynamic>>);
	NullableEnum(value:Null<Enum<Dynamic>>);
	Pair(first:Class<Dynamic>, second:Enum<Dynamic>);
}

/** Construction must execute even when its result is used only to query its class. */
class Item {
	public function new() {
		Sys.println("construct");
	}
}

/** Observe native descriptor transport without introducing first-class type literals. */
class Main {
	static function selectedClass():Class<Dynamic> {
		Sys.println("class");
		return Types.getClass(new Item());
	}

	static function selectedEnum():Enum<Dynamic> {
		Sys.println("enum");
		return Types.getEnum(Token.Mark);
	}

	static function main():Void {
		final selected = Types.getClass(new Item());
		switch Payload.ClassValue(selected) {
			case ClassValue(stored):
				Sys.println(Types.getClassName(stored));
				Sys.println(stored == selected);
			case _:
				throw "class payload";
		}
		final selectedType = Types.getEnum(Token.Mark);
		switch Payload.EnumType(selectedType) {
			case EnumType(stored):
				Sys.println(Types.getEnumName(stored));
				Sys.println(stored == selectedType);
			case _:
				throw "enum payload";
		}
		switch Payload.OptionalClass() {
			case OptionalClass(stored):
				Sys.println(stored == null);
			case _:
				throw "omitted class";
		}
		switch Payload.OptionalEnum() {
			case OptionalEnum(stored):
				Sys.println(stored == null);
			case _:
				throw "omitted enum";
		}
		switch Payload.NullableClass(null) {
			case NullableClass(stored):
				Sys.println(stored == null);
			case _:
				throw "null class";
		}
		switch Payload.NullableEnum(null) {
			case NullableEnum(stored):
				Sys.println(stored == null);
			case _:
				throw "null enum";
		}
		switch Payload.OptionalClass(selected) {
			case OptionalClass(stored):
				Sys.println(stored == selected);
			case _:
				throw "present class";
		}
		switch Payload.OptionalEnum(selectedType) {
			case OptionalEnum(stored):
				Sys.println(stored == selectedType);
			case _:
				throw "present enum";
		}
		switch Payload.NullableClass(selected) {
			case NullableClass(stored):
				Sys.println(stored == selected);
			case _:
				throw "nullable class";
		}
		switch Payload.NullableEnum(selectedType) {
			case NullableEnum(stored):
				Sys.println(stored == selectedType);
			case _:
				throw "nullable enum";
		}
		switch Payload.Pair(selectedClass(), selectedEnum()) {
			case Pair(first, second):
				Sys.println(Types.getClassName(first));
				Sys.println(Types.getEnumName(second));
			case _:
				throw "ordered pair";
		}
		final absent:Item = null;
		Sys.println(Types.getClass(absent) == null);
	}
}
