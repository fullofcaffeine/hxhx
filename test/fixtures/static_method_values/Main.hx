import Provider.choose as selected;
import Alternate.choose as alternate;

/** Aliases and local shadowing must preserve the selected static method. */
class Main {
	static function main():Void {
		final first = selected;
		final qualified = Provider.choose;
		final second = alternate;
		trace(first(3));
		trace(qualified(4));
		trace(second(5));
		{
			final selected = Alternate.choose;
			trace(selected(7));
		}
	}
}
