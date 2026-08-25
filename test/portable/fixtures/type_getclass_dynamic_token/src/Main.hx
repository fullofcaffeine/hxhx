package;

class Main {
	static function main() {
		final reflected:Dynamic = Type.getClass([]);
		Sys.println("direct=" + (reflected == Array));

		// Haxe gives these two branch constants the same source span. They must
		// still keep separate output identities in the target switch.
		final selected = switch (reflected) {
			case Array, String: "known";
			default: "other";
		};
		Sys.println("switch=" + selected);

		Sys.println("null=" + (Type.getClass(null) == null));
		Sys.println("primitive=" + (Type.getClass(1) == null));
	}
}
