class UnclosedMain {
	static function main():Void {
		// The `${` below is never closed: upstream reports it at the brace.
		Fmt.formatAt("x ${a y", "src/UnclosedMain.hx", 138);
	}
}
