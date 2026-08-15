private class ObjKey {
	public final id:Int;

	public function new(id:Int) {
		this.id = id;
	}
}

private typedef StoredEntry = {
	var key:String;
	var value:Int;
}

class MapMain {
	static function validateStoredEntry(entry:StoredEntry):Int {
		if (entry.key != "plain")
			throw "stored_entry_key";
		return entry.value;
	}

	static function main() {
		// String keys -> StringMap specialization
		final sm:Map<String, Int> = new Map();
		sm.set("a", 1);
		sm.set("b", 2);

		if (sm.get("a") != 1)
			throw "sm_get";
		if (sm.get("missing") != null)
			throw "sm_missing";
		if (!sm.exists("b"))
			throw "sm_exists";
		if (!sm.remove("b"))
			throw "sm_remove_true";
		if (sm.remove("b"))
			throw "sm_remove_false";
		if (sm.exists("b"))
			throw "sm_removed";

		sm.set("c", 3);
		sm.set("d", 4);

		final keys:Array<String> = [];
		final kit = sm.keys();
		while (kit.hasNext())
			keys.push(kit.next());
		keys.sort((x, y) -> x < y ? -1 : (x > y ? 1 : 0));
		if (keys.join(",") != "a,c,d")
			throw "sm_keys";

		var sum = 0;
		final vit = sm.iterator();
		while (vit.hasNext())
			sum += vit.next();
		if (sum != 8)
			throw "sm_values";

		var kvSum = 0;
		final kvi = sm.keyValueIterator();
		while (kvi.hasNext()) {
			final kv = kvi.next();
			if (!sm.exists(kv.key))
				throw "sm_kv_key";
			kvSum += kv.value;
		}
		if (kvSum != sum)
			throw "sm_kv_sum";

		final stored:StoredEntry = {key: "plain", value: 7};
		if (validateStoredEntry(stored) != 7)
			throw "stored_entry_value";

		// Int keys -> IntMap specialization
		final im:Map<Int, String> = new Map();
		im.set(10, "x");
		im.set(20, "y");
		if (im.get(10) != "x")
			throw "im_get";
		if (im.get(999) != null)
			throw "im_missing";

		final ikeys:Array<Int> = [];
		final ik = im.keys();
		while (ik.hasNext())
			ikeys.push(ik.next());
		ikeys.sort((a, b) -> a - b);
		if (ikeys.join(",") != "10,20")
			throw "im_keys";

		var intPairCount = 0;
		final ikvi = im.keyValueIterator();
		while (ikvi.hasNext()) {
			final kv = ikvi.next();
			if (!im.exists(kv.key) || kv.value.length != 1)
				throw "im_kv";
			intPairCount++;
		}
		if (intPairCount != 2)
			throw "im_kv_count";

		// Object keys -> ObjectMap specialization (identity)
		final om:Map<ObjKey, Int> = new Map();
		final o1 = new ObjKey(1);
		final o1b = new ObjKey(1);
		om.set(o1, 123);
		if (om.get(o1) != 123)
			throw "om_get";
		if (om.get(o1b) != null)
			throw "om_identity";
		if (!om.exists(o1))
			throw "om_exists";

		var objectPairCount = 0;
		final okvi = om.keyValueIterator();
		while (okvi.hasNext()) {
			final kv = okvi.next();
			if (kv.key != o1 || kv.value != 123)
				throw "om_kv";
			objectPairCount++;
		}
		if (objectPairCount != 1)
			throw "om_kv_count";

		if (!om.remove(o1))
			throw "om_remove";
		if (om.exists(o1))
			throw "om_removed";
	}
}
