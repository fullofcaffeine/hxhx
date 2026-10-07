/** Observes overrides, mutation, identity and null through recursive exports. */
class Main {
	static function main():Void {
		final child = new Child(3);
		final base:Base = child;
		Sys.println(First.observe(base));
		final retained = First.retain(base);
		child.count = 7;
		Sys.println(First.observe(retained));
		Sys.println(retained == base);
		Sys.println(First.maybe(null));
		Sys.println(First.child(child) == child);
		Sys.println(child.marker());
	}
}
