package shadows;

/** The interval's root provider stays distinct from a class in this source package. */
class Main {
	static function main():Void {
		trace("RANGE|shadow:" + new IntIterator().label());
		final span = 2...4;
		trace("RANGE|next:" + span.next());
		trace("RANGE|next:" + span.next());
		trace("RANGE|end:" + span.hasNext());
	}
}
