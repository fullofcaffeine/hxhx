/** Independent native reference; supplementary characters distinguish UTF-16 units from UTF-8 bytes. */
class Main {
	static function main():Void {
		Sys.println(StringLength.read(""));
		Sys.println(StringLength.read("abc"));
		Sys.println(StringLength.read("é"));
		Sys.println(StringLength.read("😀"));
		Sys.println(StringLength.read("é"));
		Sys.println(StringLength.read("Aé😀Z"));
		Sys.println(StringLength.read("a\x00b"));
		Sys.println(StringLength.read(null));
		var calls = 0;
		Sys.println(StringLength.boundary(() -> {
			calls++;
			return "😀!";
		}));
		Sys.println(calls);
		Sys.println(StringLength.shadow(new StringLength.LengthOwner()));
	}
}
