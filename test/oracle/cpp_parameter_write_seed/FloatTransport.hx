/** Typed Float writes copy existing values without arithmetic, parsing, or erasure. */
class FloatTransport {
	public static function replace(value:Float, next:Float):Float {
		return value = next;
	}

	public static function throughClosure(value:Float, next:Float):Float {
		final change = (parameter:Float) -> {
			parameter = next;
			return parameter;
		};
		return change(value);
	}
}
