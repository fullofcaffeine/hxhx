class Main {
	/** Splits commas while preserving parenthesized groups. */
	static function splitTopLevel(source:String):Array<String> {
		final output = new Array<String>();
		if (StringTools.trim(source).length == 0)
			return output;
		var start = 0;
		var depth = 0;
		var index = 0;
		while (index < source.length) {
			switch (source.charCodeAt(index)) {
				case "(".code:
					depth++;
				case ")".code:
					depth--;
				case ",".code:
					if (depth == 0) {
						output.push(StringTools.trim(source.substr(start, index - start)));
						start = index + 1;
					}
				case _:
			}
			index++;
		}
		output.push(StringTools.trim(source.substr(start)));
		return output;
	}

	static function main():Void {
		Sys.println(splitTopLevel("a, (b,c), d").join("|"));
		Sys.println("empty=" + splitTopLevel("").length);
	}
}
