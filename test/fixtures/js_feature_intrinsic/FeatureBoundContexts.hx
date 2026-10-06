/** Method values can originate in static values, instance values, constructors and parenthesized expressions. */
class FeatureBoundContexts {
	static var callback:Void->String = new ContextReceiver("static").read;

	static function main():Void {
		trace(callback());
		final holder = new ContextHolder(new ContextReceiver("constructor"));
		trace(holder.initial());
		trace(holder.constructed());
		final receiver = new ContextReceiver("local");
		final __hx_bind_method = "shadow";
		final selected = (receiver.read);
		trace(selected());
		trace((receiver.read)());
		trace(__hx_bind_method);
		final old = receiver.replaceable;
		receiver.replaceable = replacement;
		final newer = receiver.replaceable;
		receiver.label = "changed";
		trace(old());
		trace(newer());
		trace(old == newer);
		trace(newer == receiver.replaceable);
	}

	static function replacement():String {
		return "replacement";
	}
}

/** Field initializer and constructor method reads own separate executable catalogs. */
class ContextHolder {
	public var initial:Void->String = new ContextReceiver("instance").read;
	public var constructed:Void->String;

	public function new(receiver:ContextReceiver) {
		constructed = receiver.read;
	}
}

/** Receiver state remains live, while a stored method retains the function selected at read time. */
class ContextReceiver {
	public var label:String;

	public function new(label:String) {
		this.label = label;
	}

	public function read():String {
		return label;
	}

	public dynamic function replaceable():String {
		return "old:" + label;
	}
}
