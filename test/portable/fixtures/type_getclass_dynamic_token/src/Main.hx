package;

class Main {
	static function main() {
		final reflected:Dynamic = Type.getClass([]);
		Sys.println("direct=" + (reflected == Array));

		final selected = switch (reflected) {
			case Array, String: "known";
			default: "other";
		};
		Sys.println("switch=" + selected);

		Sys.println("null=" + (Type.getClass(null) == null));
		Sys.println("primitive=" + (Type.getClass(1) == null));
	}
}
