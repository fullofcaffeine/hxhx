package model;

/** A distinct nominal type with an overlapping field, used to reject foreign proof reuse. */
class OtherPayload {
	public var count:Int;

	public function new(count:Int) {
		this.count = count;
	}
}
