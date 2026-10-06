/** Independent behavioral expectations for upstream Haxe 4.3.7/hxcpp. */
class ReferenceMain {
	static function main():Void {
		final payload = [7];
		final any:Dynamic = CatchControl.any(payload);
		if (any != payload)
			throw "Any catch changed payload identity";
		if (CatchControl.select(payload) != payload
			|| CatchControl.expression(payload) != payload
			|| CatchControl.nested(payload) != payload)
			throw "catch changed payload identity";
		if (CatchControl.select(null) != null || CatchControl.loops() != 2)
			throw "catch changed null or loop control";
		if (CatchControl.inside(payload)() != payload)
			throw "closure handler changed payload identity";
		final first = CatchControl.capture(payload);
		final second = CatchControl.capture([9]);
		if (first(null) != payload || second(null)[0] != 9 || first(null) != null)
			throw "catch closure lost independent state";
	}
}
