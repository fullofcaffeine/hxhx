class Main {
	static function main() {
		final r = new EReg("\\d+", "g");
		Sys.println("m=" + r.match("ab12cd"));
		Sys.println("g0=" + r.matched(0));
		final p = r.matchedPos();
		Sys.println("pos=" + p.pos + ",len=" + p.len);
		Sys.println("left=" + r.matchedLeft());
		Sys.println("right=" + r.matchedRight());
		Sys.println("rep=" + r.replace("a1b22c", "#"));
		final parts = r.split("a1b22c");
		Sys.println("parts=" + parts.join("|"));
		Sys.println("map=" + r.map("a1b22c", (e) -> "[" + e.matched(0) + "]"));
		Sys.println("esc=" + EReg.escape("a+b"));
		final names:Array<String> = [];
		final constructors = ~/\bnew\s+([A-Z][A-Za-z0-9_]*)\b/g;
		constructors.map("é😀é😀é😀é😀é😀é😀 new First() new Later()", matched -> {
			names.push(matched.matched(1));
			return matched.matched(0);
		});
		Sys.println("unicode-map=" + names.join("|"));
		Sys.println("OK ereg_basic");
	}
}
