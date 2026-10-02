import hxhxmacrohost.api.RuntimeMacroExprs;

/** Keep every authored comprehension wrapper visible through the public runtime macro parser. */
class M14SourceComprehensionSyntaxTest {
	static function main():Void {
		final expected = ComprehensionContract.expected().split("\n");
		final sources = ComprehensionContract.sources();
		final failures = new Array<String>();
		for (index in 0...sources.length) {
			var actual = "";
			try {
				actual = ComprehensionContract.shape(RuntimeMacroExprs.parse(sources[index], null));
			} catch (error:haxe.Exception) {
				actual = "rejected: " + error.message;
			} catch (error:HxParseError) {
				actual = "rejected: " + error.toString();
			}
			if (actual != expected[index])
				failures.push(sources[index] + "\nexpected: " + expected[index] + "\nactual: " + actual);
		}
		if (failures.length > 0)
			throw failures.join("\n");
		Sys.println("SOURCE_COMPREHENSION_SYNTAX:PASS");
	}
}
