/** Independent upstream execution of the same authored loop methods. */
class Main {
	static function main():Void {
		Sys.println(RootLoops.nulls());
		Sys.println(RootLoops.indexed());
		Sys.println(RootLoops.nested());
		Sys.println(RootLoops.captures());
		Sys.println(RootLoops.range());
		Sys.println(RootLoops.repeated());
		Sys.println(RootLoops.early());
		Sys.println(RootLoops.rangeCaptures());
	}
}
