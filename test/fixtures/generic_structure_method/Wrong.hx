class Fixed {
	public function new() {}

	public function get():String
		return "fixed";
}

class Wrong {
	static function main() {
		final value:{function get<T>():T;} = new Fixed();
		Sys.println(value.get());
	}
}
