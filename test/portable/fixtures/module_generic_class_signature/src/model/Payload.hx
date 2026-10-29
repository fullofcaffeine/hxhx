package model;

/** A mutable object whose aliases must survive generic callback conversion. */
class Payload {
	public var count:Int;
	public final children:Array<Payload> = [];
	public var parent:Null<Payload> = null;

	public function new(count:Int) {
		this.count = count;
	}
}
