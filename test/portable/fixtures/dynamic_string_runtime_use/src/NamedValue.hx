class NamedValue {
	public final value:Int;

	public function new(value:Int) {
		this.value = value;
	}

	public function toString():String {
		return 'named:$value';
	}
}
