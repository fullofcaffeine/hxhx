import haxe.Constraints.IMap;

/** Proves that a static concrete Map cannot become `IMap` without a conversion plan. */
class UnsealedIMapConversionRejected {
	static final map:IMap<String, Int> = new haxe.ds.StringMap<Int>();

	static function main():Void {}
}
