private class HashKey {
	public final id:Int;

	public function new(id:Int) {
		this.id = id;
	}

	public function hashCode():Int {
		return id;
	}
}

class Main {
	static function main() {
		final arrayIterator = new haxe.iterators.ArrayIterator([3, 4, 5]);
		var arraySum = 0;
		while (arrayIterator.hasNext()) {
			arraySum += arrayIterator.next();
		}
		Sys.println("array.sum=" + arraySum);

		final arrayKeyValueIterator = new haxe.iterators.ArrayKeyValueIterator(["a", "b"]);
		var arrayKeySum = 0;
		var arrayValueLen = 0;
		while (arrayKeyValueIterator.hasNext()) {
			final pair = arrayKeyValueIterator.next();
			arrayKeySum += pair.key;
			arrayValueLen += pair.value.length;
		}
		Sys.println("array.kv=" + arrayKeySum + ":" + arrayValueLen);

		final access:haxe.DynamicAccess<Int> = new haxe.DynamicAccess<Int>();
		access["x"] = 2;
		access["y"] = 5;

		final dynamicAccessIterator = new haxe.iterators.DynamicAccessIterator(access);
		var dynSum = 0;
		while (dynamicAccessIterator.hasNext()) {
			dynSum += dynamicAccessIterator.next();
		}
		Sys.println("dynamic.sum=" + dynSum);

		final dynamicAccessKeyValueIterator = new haxe.iterators.DynamicAccessKeyValueIterator(access);
		var dynKeyLen = 0;
		var dynValueSum = 0;
		while (dynamicAccessKeyValueIterator.hasNext()) {
			final pair = dynamicAccessKeyValueIterator.next();
			dynKeyLen += pair.key.length;
			dynValueSum += pair.value;
		}
		Sys.println("dynamic.kv=" + dynKeyLen + ":" + dynValueSum);

		final hashMap = new haxe.ds.HashMap<HashKey, String>();
		hashMap.set(new HashKey(1), "one");
		hashMap.set(new HashKey(2), "two");
		final hashMapIterator = new haxe.iterators.HashMapKeyValueIterator(hashMap);
		var hashCount = 0;
		while (hashMapIterator.hasNext()) {
			hashMapIterator.next();
			hashCount += 1;
		}
		Sys.println("hashmap.count=" + hashCount);

		final stringMap = new haxe.ds.StringMap<Int>();
		stringMap.set("aa", 1);
		stringMap.set("bbb", 2);
		final mapIterator = new haxe.iterators.MapKeyValueIterator(stringMap);
		var mapKeyLen = 0;
		var mapValueSum = 0;
		while (mapIterator.hasNext()) {
			final pair = mapIterator.next();
			mapKeyLen += pair.key.length;
			mapValueSum += pair.value;
		}
		Sys.println("map.kv=" + mapKeyLen + ":" + mapValueSum);

		final rest = haxe.Rest.of([10, 20, 30]);
		final restIterator = rest.iterator();
		var restSum = 0;
		while (restIterator.hasNext()) {
			restSum += restIterator.next();
		}
		Sys.println("rest.sum=" + restSum);

		final restKeyValueIterator = rest.keyValueIterator();
		var restKeySum = 0;
		var restValueSum = 0;
		while (restKeyValueIterator.hasNext()) {
			final pair = restKeyValueIterator.next();
			restKeySum += pair.key;
			restValueSum += pair.value;
		}
		Sys.println("rest.kv=" + restKeySum + ":" + restValueSum);

		final stringIterator = new haxe.iterators.StringIterator("AZ");
		var stringCodeSum = 0;
		while (stringIterator.hasNext()) {
			stringCodeSum += stringIterator.next();
		}
		Sys.println("string.iter=" + stringCodeSum);

		final stringIteratorUnicode = new haxe.iterators.StringIteratorUnicode("AZ");
		var stringUnicodeSum = 0;
		while (stringIteratorUnicode.hasNext()) {
			stringUnicodeSum += stringIteratorUnicode.next();
		}
		Sys.println("string.iterU=" + stringUnicodeSum);

		final stringKeyValueIterator = new haxe.iterators.StringKeyValueIterator("AZ");
		var stringKeySum = 0;
		var stringValueSum = 0;
		while (stringKeyValueIterator.hasNext()) {
			final pair = stringKeyValueIterator.next();
			stringKeySum += pair.key;
			stringValueSum += pair.value;
		}
		Sys.println("string.kv=" + stringKeySum + ":" + stringValueSum);

		final stringKeyValueIteratorUnicode = new haxe.iterators.StringKeyValueIteratorUnicode("AZ");
		var stringUnicodeKeySum = 0;
		var stringUnicodeValueSum = 0;
		while (stringKeyValueIteratorUnicode.hasNext()) {
			final pair = stringKeyValueIteratorUnicode.next();
			stringUnicodeKeySum += pair.key;
			stringUnicodeValueSum += pair.value;
		}
		Sys.println("string.kvU=" + stringUnicodeKeySum + ":" + stringUnicodeValueSum);
		Sys.println("html.escape=" + StringTools.htmlEscape("<A&B>", true));
	}
}
