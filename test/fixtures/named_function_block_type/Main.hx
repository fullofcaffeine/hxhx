/** A block ending in a declared Boolean function call retains its result type. */
class Main {
	static function main():Void {
		final selected = switch (1) {
			case 1:
				function accept():Bool {
					return true;
				}
				accept();
			default: false;
		};
		if (selected != true)
			throw "lost Boolean result";
		shadow();
	}

	/** The replay declaration shadows an outer callable only inside its own block. */
	static function shadow():Void {
		final accept = function():String {
			return "outer";
		};
		final selected = {
			function accept():Bool {
				return true;
			}
			accept();
		};
		if (selected != true || accept() != "outer")
			throw "lost lexical shadow boundary";
	}
}
