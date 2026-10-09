/** Feature-selected branches must retain their own effects and execute only when selected. */
class Main {
	static function main():Void {
		untyped __define_feature__("probe.enabled", true);
		untyped __feature__("probe.enabled", {
			trace("enabled");
			trace("branch");
		}, trace("wrong:disabled"));
		untyped __feature__("probe.absent", trace("wrong:enabled"), trace("absent"));
	}
}
