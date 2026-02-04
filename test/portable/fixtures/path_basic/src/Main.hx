import haxe.io.Path;

class Main {
	static function main() {
		final join1 = Path.join(["", "/a", "b", "", "c.hx"]);
		Sys.println("join1=" + join1);

		// Use a Windows-style path (single backslashes in the runtime value).
		final norm1 = Path.normalize("C:\\a\\b\\..\\c");
		Sys.println("norm1=" + norm1);

		final trail1 = Path.addTrailingSlash("a/b");
		Sys.println("trail1=" + trail1);

		final abs1 = Path.isAbsolute("/root");
		Sys.println("abs1=" + (abs1 ? "yes" : "no"));
	}
}
