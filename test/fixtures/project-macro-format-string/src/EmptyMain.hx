class EmptyMain {
	static function main():Void {
		// An empty `${ }`: upstream reports it at the space inside.
		Fmt.formatAt("x ${ } y", "src/EmptyMain.hx", 127);
	}
}
