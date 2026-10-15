/** Upstream assertions include finite Float values without depending on native comparison lowering. */
class Oracle {
	static function main():Void {
		@:privateAccess Main.main();
		final original = 1.25;
		if (FloatTransport.replace(original, 2.5) != 2.5 || original != 1.25)
			throw "Float parameter copy changed caller storage";
		if (FloatTransport.throughClosure(original, -4.5) != -4.5)
			throw "Float closure parameter copy changed its result";
	}
}
