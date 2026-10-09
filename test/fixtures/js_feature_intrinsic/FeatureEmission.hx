import FeatureEmissionProviders.RetainedProvider;

/** Observe initializer effects and secondary-type retention before feature selection. */
class FeatureEmission {
	static var unused:Int = initialize();

	static function initialize():Int {
		trace("unused:effect");
		return 1;
	}

	static function main():Void {
		untyped __feature__("emission.absent", trace(ConditionalProvider.value), trace("absent"));
		trace(RetainedProvider.value);
	}
}

/** This field is referenced only inside an unselected feature branch. */
class ConditionalProvider {
	public static var value:Int = initialize();

	static function initialize():Int {
		trace("conditional:effect");
		return 2;
	}
}
