/** Independent runtime expectations for the corresponding shared typing fixture. */
class MapOracle {
	static function main():Void {
		for (map in [MapCollection.plain(), MapCollection.grouped(), MapCollection.nested()])
			if (map.get(1) != 2 || map.get(2) != 3)
				throw "grouped map comprehension changed entries";
		final guarded = MapCollection.guarded();
		if (guarded.exists(1) || guarded.get(2) != 3 || guarded.get(3) != 4)
			throw "map guard changed entries";
		final indexed = MapCollection.indexed();
		if (indexed.get(0) != 5 || indexed.get(1) != 8)
			throw "map yield lost array key/value bindings";
		final branches = MapCollection.branches();
		if (branches.get(1) != 10 || branches.get(2) != 20)
			throw "map branch selected a wrong value";
		final loops = MapCollection.loops();
		if (loops.get(13) != 3 || loops.get(14) != 4 || loops.get(23) != 3 || loops.get(24) != 4)
			throw "nested map loop lost entries";
		final values = MapCollection.mapValues();
		if (values.length != 2 || values[0].get(1) != 2 || values[1].get(2) != 3)
			throw "array of maps changed collection kind";
		final qualified = MapCollection.qualifiedMapValues();
		if (qualified.length != 2 || qualified[0].get(1) != 2 || qualified[1].get(2) != 3)
			throw "qualified array of maps changed collection kind";
		Sys.println("SOURCE_MAP_COMPREHENSION_ORACLE:PASS");
	}
}
