/** Compare the same source constants against independent values on upstream C++. */
class OracleMain {
	static function main():Void {
		Main.main();
		if (Main.ascii != 65 || Main.emoji != 128512 || Main.escaped != 233 || Main.maximum != 1114111 || Main.newline != 10 || Main.nul != 0
			|| Main.octal != 65 || Main.space != 32)
			throw "literal character code differs from its Unicode scalar";
		Sys.println("CPP_LITERAL_CHARACTER_CODE:PASS");
	}
}
