/** Independent upstream behavior for declared, nonempty Map literals. */
class Main {
	static function main():Void {
		if (Entries.field.get("value") != true)
			throw "field";
		for (map in [
			Entries.returned(1.5),
			Entries.local(1.5),
			Entries.assigned([], 1.5),
			Entries.argument(1.5)
		])
			if (map.get("value") != 1.5)
				throw "float value";
		if (Entries.nested(true).get("value").item != true)
			throw "nested";
		if (Entries.generic("ok").get("value") != "ok")
			throw "generic";
		if (!Entries.callback().get("value")(true))
			throw "callback";
		if (Entries.mixed().get("boolean") != true || Entries.mixed().get("text") != "ok")
			throw "mixed";
		if (Entries.ordinary(1.5)[0] != 1.5)
			throw "ordinary";
	}
}
