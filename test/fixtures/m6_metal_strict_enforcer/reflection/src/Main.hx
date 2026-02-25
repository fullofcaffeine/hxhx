class Main {
	static function main():Void {
		final payload = {answer: 42};
		final reflected = Reflect.field(payload, "answer");
		final resolved = Type.resolveClass("Main");
		trace(reflected);
		trace(resolved);
	}
}
