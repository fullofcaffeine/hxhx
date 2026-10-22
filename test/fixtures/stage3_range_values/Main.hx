/** A first-class interval is one mutable cursor; a direct loop keeps its bound snapshots. */
class Main {
	static function bound(name:String, value:Int):Int {
		trace("RANGE|bound:" + name);
		return value;
	}

	static function main():Void {
		final span = bound("start", 2)...bound("end", 6);
		final alias = span;
		trace("RANGE|has:" + span.hasNext());
		trace("RANGE|partial:" + alias.next());
		var sum = 0;
		for (value in span)
			sum += value;
		trace("RANGE|remaining:" + sum);
		trace("RANGE|exhausted:" + alias.hasNext());
		var repeated = 0;
		for (value in alias)
			repeated++;
		trace("RANGE|repeated:" + repeated);
		var direct = 0;
		for (value in bound("direct-start", 2)...bound("direct-end", 6))
			direct += value;
		trace("RANGE|direct:" + direct);
		final empty = 4...4;
		final reverse = bound("reverse-start", 5)...bound("reverse-end", 2);
		var count = 0;
		for (value in empty)
			count++;
		for (value in reverse)
			count++;
		trace("RANGE|empty:" + count);
		final early = 1...5;
		for (value in early) {
			trace("RANGE|break:" + value);
			break;
		}
		trace("RANGE|after-break:" + early.next());
		final left = 1...3;
		final right = 1...3;
		trace("RANGE|left:" + left.next());
		trace("RANGE|right:" + right.next());
		final doubled = [for (value in 1...4) value * 2];
		trace("RANGE|comprehension:" + doubled.length + ":" + doubled[0] + ":" + doubled[2]);
		final explicit = new IntIterator(3, 5);
		trace("RANGE|explicit:" + explicit.next());
		var tail = 0;
		for (value in explicit)
			tail += value;
		trace("RANGE|explicit-tail:" + tail);
	}
}
