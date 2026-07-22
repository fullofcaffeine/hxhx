package hxhx;

/**
	Stores one stop-after-reply decision for the socket transport.

	`take` clears the decision as it returns it. A failed response write can
	therefore discard its own decision without allowing a later connection to
	inherit it.
**/
class CompilationServerStopSignal {
	var requested = false;

	public function new() {}

	public function record(value:Bool):Void {
		requested = value;
	}

	public function take():Bool {
		if (!requested)
			return false;
		requested = false;
		return true;
	}
}
