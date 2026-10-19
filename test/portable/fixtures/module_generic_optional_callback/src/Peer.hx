/** The cycle exports concrete return types instead of inferring a polymorphic producer. */
class Peer {
	public static function source(value:Value):Source {
		return Item(value);
	}

	public static function produce(build:() -> Value):Value {
		return build();
	}

	public static function observe(scope:Scope):Void {
		if (scope.depth < 1)
			throw "scope not entered";
	}
}
