import shadows.IntIterator;

/** Imported type names govern ordinary new expressions, not the interval operator. */
class Main {
	static function main():Void {
		trace("RANGE|shadow:" + new IntIterator().label());
		final span = 2...4;
		trace("RANGE|next:" + span.next());
		trace("RANGE|next:" + span.next());
		trace("RANGE|end:" + span.hasNext());
	}
}
