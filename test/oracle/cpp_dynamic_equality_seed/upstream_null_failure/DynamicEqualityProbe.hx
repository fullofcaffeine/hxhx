/** Reduced upstream native crash: enum comparison with a non-null left payload and null right payload. */
class DynamicEqualityProbe {
	static function main():Void {
		final left:Dynamic = Sample.Opaque(false);
		final right:Dynamic = Sample.Opaque(null);
		Sys.println(left == right);
	}
}

enum Sample {
	Opaque(value:Dynamic);
}
