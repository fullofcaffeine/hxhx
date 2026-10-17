/** An enum used only as input, without an enum-returning helper to register it. */
enum Token {
	Label(text:String);
	Items(values:Array<String>);
}
