/** A storage type alone does not permit an implicit abstract input. */
class AbstractMissingHeader {
	static function main():Void {
		final values:Array<String> = ["value"];
		final holder = new Holder(values);
	}
}

abstract Box<T>(Array<T>) {}

class Holder<T> {
	public function new(value:Box<T>) {}
}
