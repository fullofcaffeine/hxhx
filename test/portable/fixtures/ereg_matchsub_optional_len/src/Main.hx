class Main {
	static function main() {
		final sb = new StringBuf();
		for (i in 0...400) {
			if (i > 0)
				sb.add(",");
			sb.add("item");
			sb.add(Std.string(i));
		}

		final source = sb.toString();
		final re = new EReg("item(\\d+)", "g");

		var total = 0;
		for (_ in 0...250) {
			var pos = 0;
			while (re.matchSub(source, pos)) {
				final mp = re.matchedPos();
				total++;
				pos = mp.pos + mp.len;
			}
		}

		final first = new EReg("item(\\d+)", "g");
		final firstOk = first.matchSub(source, 0);
		Sys.println("total=" + total);
		Sys.println("first=" + firstOk + ":" + first.matched(1));
		Sys.println("OK ereg_matchsub_optional_len");
	}
}
