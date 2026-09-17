package ordinary;

/** An ordinary object whose qualified name must not select a core primitive. */
class String {
	public final value:Int;

	public function new(number:Int) {
		value = number;
	}
}
