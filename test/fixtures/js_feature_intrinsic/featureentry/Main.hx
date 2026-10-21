package featureentry;

/** A packaged entry must select its exact class, even when a secondary class also declares main. */
class Main {
	static function main():Void {
		untyped __define_feature__("entry.selected", true);
		untyped __feature__("entry.selected", trace("packaged:on"), trace("packaged:off"));
	}
}

/** Loading a source module must not make this function the request's entry point. */
class Secondary {
	static function main():Void {
		trace("wrong:secondary");
	}
}
