/** Fixing a callback parameter to a base class must still admit a derived argument. */
class FeatureBoundSubtype {
	static function main():Void {
		final receiver = new SubtypeReceiver();
		final callback:CallbackBase->CallbackBase = receiver.echo;
		final result = callback(new CallbackChild());
		trace(result.name());
	}
}

/** The stored generic method receives its base-class context from the local declaration. */
class SubtypeReceiver {
	public function new() {}

	public function echo<T>(value:T):T {
		return value;
	}
}

/** This declared callback type remains stable when a derived argument is supplied. */
class CallbackBase {
	public function new() {}

	public function name():String {
		return "base";
	}
}

/** The result keeps the actual object's virtual behavior despite its base static type. */
class CallbackChild extends CallbackBase {
	public function new() {
		super();
	}

	override public function name():String {
		return "child";
	}
}
