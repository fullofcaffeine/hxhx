/** The module's primary declaration is unused although its secondary type is referenced. */
class FeatureEmissionProviders {
	static function __init__():Void {
		trace("primary:effect");
	}
}

/** Retention must preserve the secondary type's original module identity. */
class RetainedProvider {
	public static var value:Int = 3;
}
