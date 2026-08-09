private class ObjectKey {
	public final id:Int;

	public function new(id:Int) {
		this.id = id;
	}
}

/**
	Defines how a nullable standard Map behaves before it reaches an `IMap` call.

	Each non-null case stores a concrete Map in a nullable static field, then uses
	the field through the ordinary Map API. The null case catches the error from a
	real operation so the target cannot replace null with an empty or boxed Map.
**/
class Main {
	static var strings:Null<Map<String, Int>> = null;
	static var ints:Null<Map<Int, String>> = null;
	static var objects:Null<Map<ObjectKey, Int>> = null;

	static function emit(line:String):Void {
		#if js
		js.Syntax.code("console.log({0})", line);
		#else
		Sys.println(line);
		#end
	}

	static function stringValue():Null<Int> {
		final created:Map<String, Int> = [];
		created.set("one", 1);
		strings = created;
		return strings.get("one");
	}

	static function intValue():Null<String> {
		final created:Map<Int, String> = [];
		created.set(2, "two");
		ints = created;
		return ints.get(2);
	}

	static function objectValue():Null<Int> {
		final key = new ObjectKey(3);
		final created:Map<ObjectKey, Int> = [];
		created.set(key, 3);
		objects = created;
		return objects.get(key);
	}

	static function nullReadThrows():Bool {
		strings = null;
		try {
			strings.get("missing");
			return false;
		} catch (_:Dynamic) {
			return true;
		}
	}

	static function main():Void {
		emit("string=" + stringValue());
		emit("int=" + intValue());
		emit("object=" + objectValue());
		emit("nullThrows=" + nullReadThrows());
	}
}
