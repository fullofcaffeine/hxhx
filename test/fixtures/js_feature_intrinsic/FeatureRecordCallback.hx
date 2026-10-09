/** Record callbacks have structural types, while their referenced functions retain exact declarations. */
class FeatureRecordCallback {
	static function callback(key:String):Bool {
		untyped __define_feature__("record.callback", true);
		return key == "key";
	}

	static function record():{test:String->Bool} {
		untyped __define_feature__("record.receiver", true);
		return {test: callback};
	}

	static function typed(value:{test:String->Bool}):Bool
		return value.test("key");

	/** Model the standard library's unchecked foreign-object boundary. */
	static function inferred(value:Dynamic):Bool
		return (cast value).test("key");

	static function main():Void {
		untyped __feature__("record.callback", trace("callback:on"), trace("callback:off"));
		untyped __feature__("record.receiver", trace("receiver:on"), trace("receiver:off"));
		trace(typed(record()));
		trace(inferred(record()));
		final saved = record().test;
		trace(saved("key"));
	}
}
