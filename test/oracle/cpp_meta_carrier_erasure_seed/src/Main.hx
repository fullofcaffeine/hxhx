/** Ordinary generic class used to prove runtime class metadata erases type parameters. **/
class GenericBox<T> {
	public final value:T;

	public function new(value:T) {
		this.value = value;
	}
}

/** Enum used to prove runtime enum metadata has the same erased representation. **/
enum MetaChoice {
	Picked;
}

/**
	Repo-owned observable contract for Haxe Class<T> and Enum<T> metadata values.

	The compiler keeps the source type parameters while checking the program, but
	the runtime reflection values intentionally report only the nominal type name.
**/
class Main {
	static function emit(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	static function matches(value:Dynamic, expected:Type.ValueType):Bool {
		return Type.enumEq(Type.typeof(value), expected);
	}

	static function readBox(value:GenericBox<Int>):Int {
		return value.value;
	}

	static function main():Void {
		final box = new GenericBox(7);
		final choice = MetaChoice.Picked;

		emit("generic=" + readBox(box));
		emit("class=" + Type.getClassName(Type.getClass(box)));
		emit("resolved-class=" + Type.getClassName(Type.resolveClass("GenericBox")));
		emit("enum=" + Type.getEnumName(Type.getEnum(choice)));
		emit("resolved-enum=" + Type.getEnumName(Type.resolveEnum("MetaChoice")));
	}
}
