/** The stock compiler supplies the independent runtime expectation for collection construction. */
class CollectionOracle {
	static function main():Void {
		Sys.println(Collection.collect().join(","));
		Sys.println(Collection.guarded().join(","));
		Sys.println(Collection.chained().join(","));
		final captured = Collection.captures();
		Sys.println(captured[0]() + "," + captured[1]());
		Sys.println(Collection.nested().join(","));
		Sys.println(Collection.early().join(","));
		Sys.println(Collection.exits().join(","));
		Sys.println(Collection.indexed().join(","));
		final indexed = Collection.indexedCaptures();
		Sys.println(indexed[0]() + "," + indexed[1]());
	}
}
