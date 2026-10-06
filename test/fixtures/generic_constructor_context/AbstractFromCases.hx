/** Header conversions must participate when constructor owner arguments are omitted. */
class AbstractFromCases {
	static function operand():Array<String> {
		Sys.println("operand");
		return ["value"];
	}

	static function main():Void {
		final holder = new Holder(operand());
		Sys.println("done");
	}
}

/** The array representation is admitted explicitly through the abstract's header. */
abstract Box<T>(Array<T>) from Array<T> {
	public function wrap():Holder<T>
		return new Holder(this);
}

/** Constructor effects make operand order and allocation visible to the runtime observer. */
class Holder<T> {
	public function new(value:Box<T>) {
		Sys.println("constructed");
	}
}
