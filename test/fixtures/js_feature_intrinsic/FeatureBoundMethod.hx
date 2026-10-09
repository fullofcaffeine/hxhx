/** A stored instance method retains its receiver and participates in feature discovery. */
class FeatureBoundMethod {
	static function make(label:String):BoundReceiver {
		trace("make:" + label);
		return new BoundReceiver(label);
	}

	static function main():Void {
		untyped __feature__("bound.method", trace("bound:on"), trace("bound:off"));
		final first = make("first");
		final second = make("second");
		final selected = first.run;
		final other = second.run;
		trace(selected());
		trace(other());
		first.label = "changed";
		trace(selected());
		trace(selected == first.run);
		trace(selected == other);
		final temporary = make("temporary").run;
		trace(temporary());
	}
}

/** A bound method reads the current state of its original object on every call. */
class BoundReceiver {
	public var label:String;

	public function new(label:String) {
		this.label = label;
	}

	public function run():String {
		untyped __define_feature__("bound.method", true);
		return label;
	}
}
