/** Checks inherited mutation, constructor effects, and receiver identity. */
class Main {
	static function main():Void {
		final item = new Derived();
		Sys.println(item.baseValue);
		Sys.println(item.derivedValue);
		Sys.println(item.describe());
		Sys.println(item.saved == item);
		Sys.println(item.identity() == item);
		item.setBase(19);
		Sys.println(item.baseValue);
		Sys.println(item.saved.baseValue);
		item.adjust();
		Sys.println(item.baseValue);
		final defaults = new DefaultDerived();
		Sys.println(defaults.baseValue);
		Sys.println(defaults.extra);
		Sys.println(defaults.saved == defaults);
		final leaf = new Leaf();
		Sys.println(leaf.baseValue);
		Sys.println(leaf.derivedValue);
		Sys.println(leaf.leafValue);
		Sys.println(leaf.saved == leaf);
	}
}
