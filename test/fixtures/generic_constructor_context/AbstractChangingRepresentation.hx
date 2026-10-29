/** A header cannot silently turn array storage into a string value. */
class AbstractChangingRepresentation {
	static function main():Void {
		final values:Array<String> = ["value"];
		final holder = new Holder(values);
	}
}

abstract Box<T>(String) from Array<T> {}

class Holder<T> {
	public function new(value:Box<T>) {}
}
