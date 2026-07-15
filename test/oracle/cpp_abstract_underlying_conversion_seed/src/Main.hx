/** Generic carrier used to distinguish an abstract's storage from its conversions. **/
class ProjectionBox<T> {
	public final value:T;

	public function new(value:T) {
		this.value = value;
	}
}

/**
	Upstream Haxe 4.3.7 oracle for a generic class-backed abstract.

	The abstract must retain `ProjectionBox<T>` as its runtime carrier while
	selecting only the `@:to` conversion whose specialized argument matches `T`.
**/
abstract ProjectedValue<T>(ProjectionBox<T>) from ProjectionBox<T> {
	@:to static function projectString(value:ProjectionBox<String>):String {
		return value.value;
	}

	@:to static function projectInt(value:ProjectionBox<Int>):Int {
		return value.value;
	}
}

/** Nongeneric control that must remain outside generic carrier erasure. **/
abstract FixedProjection(ProjectionBox<String>) from ProjectionBox<String> {
	@:to static function projectFixedString(value:ProjectionBox<String>):String {
		return value.value;
	}
}

class Main {
	static function main():Void {
		final text:ProjectedValue<String> = new ProjectionBox("carrier-text");
		final projectedText:String = text;
		Sys.println(projectedText);

		final number:ProjectedValue<Int> = new ProjectionBox(42);
		final projectedNumber:Int = number;
		Sys.println(projectedNumber);

		final ordinary:ProjectionBox<Int> = new ProjectionBox(7);
		Sys.println(ordinary.value);
	}
}
