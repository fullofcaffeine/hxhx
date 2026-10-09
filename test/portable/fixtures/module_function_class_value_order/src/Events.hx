/** Observes initializer execution without relying on generated source order. */
class Events {
	public static final observed:Array<String> = [];

	public static function mark(name:String):Int {
		observed.push(name);
		return observed.length;
	}
}
