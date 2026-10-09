/** Moving callable declarations must preserve the observable order of initializers. */
private class Initialized {
	static final first:Int = Events.mark("first");
	static final second:Int = Events.mark("second");

	public static function sum():Int {
		return first + second;
	}
}

function total():Int {
	return Initialized.sum();
}
