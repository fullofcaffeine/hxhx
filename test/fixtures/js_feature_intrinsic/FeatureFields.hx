/** Field initializers use the same selected branch effects as function bodies. */
class FeatureFields {
	static var value:String = untyped __feature__("probe.field", {
		trace("field:effect");
		"selected";
	}, "fallback");

	static function main():Void {
		untyped __define_feature__("probe.field", true);
		trace(value);
	}
}
