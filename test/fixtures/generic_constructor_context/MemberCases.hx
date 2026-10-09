/** Member arguments must solve each receiver's omitted type arguments separately. */
class MemberCases {
	static function main():Void {
		final text = new Box();
		text.set("member");
		Sys.println(text.get());
		final number = new Box();
		final alias = number;
		alias.set(7);
		Sys.println(number.get());
		final widened:Box<Float> = new Box();
		widened.set(1);
		Sys.println(widened.get() + 0.5);
	}
}

/** An ordinary generic owner supplies the parameter and result contract. */
class Box<T> {
	var value:Null<T>;

	public function new() {}

	public function set(value:T):Void {
		this.value = value;
	}

	public function get():Null<T> {
		return value;
	}
}
