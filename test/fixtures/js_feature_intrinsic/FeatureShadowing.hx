/** Ordinary declarations with intrinsic-like names retain their own call identity. */
class FeatureShadowing {
	static function __define_feature__(name:String, value:String):String {
		return "method:" + name + ":" + value;
	}

	static function main():Void {
		final __feature__ = function(name:String, yes:String, no:String):String {
			return "local:" + name + ":" + yes + ":" + no;
		};
		trace(untyped __feature__("probe.shadow", "yes", "no"));
		trace(untyped __define_feature__("probe.method", "value"));
	}
}
