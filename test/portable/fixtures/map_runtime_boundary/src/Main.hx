private class ObjectKey {
	public final id:Int;

	public function new(id:Int) {
		this.id = id;
	}
}

class Main {
	static function sortedStrings(iterator:Iterator<String>):String {
		final values = [for (value in iterator) value];
		values.sort(compareText);
		return values.join(",");
	}

	static function sortedInts(iterator:Iterator<Int>):String {
		final values = [for (value in iterator) value];
		values.sort((left, right) -> left - right);
		return values.join(",");
	}

	static function compareText(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}

	static function emit(line:String):Void {
		#if js
		js.Syntax.code("console.log({0})", line);
		#else
		Sys.println(line);
		#end
	}

	static function hasMapText(text:String, expectedEntries:Array<String>):Bool {
		if (text.charAt(0) != "[" || text.charAt(text.length - 1) != "]")
			return false;
		for (entry in expectedEntries) {
			if (text.indexOf(entry) < 0)
				return false;
		}
		return true;
	}

	static function main() {
		final strings = new haxe.ds.StringMap<Int>();
		strings.set("a", 1);
		strings.set("b", 2);
		emit("string.get=" + strings.get("a"));
		emit("string.missing=" + (strings.get("missing") == null));
		emit("string.exists=" + strings.exists("b"));
		final stringRemoved = strings.remove("b");
		final stringRemovedAgain = strings.remove("b");
		emit("string.remove=" + stringRemoved + ":" + stringRemovedAgain);
		strings.set("c", 3);
		emit("string.keys=" + sortedStrings(strings.keys()));
		var stringValueSum = 0;
		for (value in strings)
			stringValueSum += value;
		emit("string.values=" + stringValueSum);
		var stringPairSum = 0;
		for (_ => value in strings)
			stringPairSum += value;
		emit("string.pairs=" + stringPairSum);
		final stringCopy = strings.copy();
		stringCopy.set("a", 9);
		emit("string.copy=" + strings.get("a") + ":" + stringCopy.get("a"));
		emit("string.text=" + hasMapText(strings.toString(), ["a => 1", "c => 3"]));
		strings.clear();
		emit("string.clear=" + !strings.keys().hasNext());

		final ints = new haxe.ds.IntMap<String>();
		ints.set(20, "y");
		ints.set(10, "x");
		emit("int.get=" + ints.get(10));
		emit("int.missing=" + (ints.get(30) == null));
		emit("int.exists=" + ints.exists(20));
		final intRemoved = ints.remove(20);
		final intRemovedAgain = ints.remove(20);
		emit("int.remove=" + intRemoved + ":" + intRemovedAgain);
		ints.set(20, "y");
		emit("int.keys=" + sortedInts(ints.keys()));
		final intValues = [for (value in ints) value];
		intValues.sort(compareText);
		emit("int.values=" + intValues.join(""));
		var intPairKeySum = 0;
		for (key => _ in ints)
			intPairKeySum += key;
		emit("int.pairs=" + intPairKeySum);
		final intCopy = ints.copy();
		intCopy.set(10, "z");
		emit("int.copy=" + ints.get(10) + ":" + intCopy.get(10));
		emit("int.text=" + hasMapText(ints.toString(), ["10 => x", "20 => y"]));
		ints.clear();
		emit("int.clear=" + !ints.iterator().hasNext());

		final first = new ObjectKey(1);
		final equalLooking = new ObjectKey(1);
		final objects = new haxe.ds.ObjectMap<ObjectKey, Int>();
		objects.set(first, 123);
		emit("object.identity=" + objects.get(first) + ":" + (objects.get(equalLooking) == null));
		emit("object.exists=" + objects.exists(first));
		var objectKeySum = 0;
		for (key in objects.keys())
			objectKeySum += key.id;
		emit("object.keys=" + objectKeySum);
		var objectValueSum = 0;
		for (value in objects)
			objectValueSum += value;
		emit("object.values=" + objectValueSum);
		var objectPairSum = 0;
		for (key => value in objects)
			objectPairSum += key.id + value;
		emit("object.pairs=" + objectPairSum);
		final objectRemoved = objects.remove(first);
		final objectRemovedAgain = objects.remove(first);
		emit("object.remove=" + objectRemoved + ":" + objectRemovedAgain);
		objects.set(first, 7);
		final objectCopy = objects.copy();
		objectCopy.set(first, 8);
		emit("object.copy=" + objects.get(first) + ":" + objectCopy.get(first));
		emit("object.text=" + hasMapText(objects.toString(), [" => 7"]));
		objects.clear();
		emit("object.clear=" + !objects.keyValueIterator().hasNext());
	}
}
