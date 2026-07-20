/** A typed value whose Boolean constructor argument is supplied through reflection. **/
class ReflectedBoolConstructor {
	public final enabled:Bool;

	public function new(enabled:Bool) {
		this.enabled = enabled;
	}
}

/** Keeps a Boolean constructor reachable through Haxe reflection. **/
class Main {
	static function main():Void {
		final value:ReflectedBoolConstructor = Type.createInstance(ReflectedBoolConstructor, [true]);
		if (!value.enabled)
			throw "reflection constructor lost its Boolean argument";
	}
}
