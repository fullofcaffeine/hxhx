class ErrorMain {
	static function main():Void {
		// The macro reports its error at the word `here` below.
		ContextProbe.fail("context error here", "src/ErrorMain.hx", 143, 147);
	}
}
