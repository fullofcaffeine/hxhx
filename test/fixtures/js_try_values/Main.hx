import haxe.Exception;

typedef TypedefToStringMap<T> = haxe.ds.StringMap<T>;
typedef Link = {final value:Int; final next:Null<Link>;}

/** Runtime expectations for typed try expressions and ordered block values. */
class Main {
	static var effects:String = "";

	static function append(value:String):Void {
		effects += value;
	}

	static function getInt():Int {
		append("g");
		return 2;
	}

	static function cond2(value:Int):Bool {
		append("c");
		return value == 2;
	}

	static function main():Void {
		final stack = try throw new Exception("") catch (e:Exception) e.stack;
		if (stack == null)
			throw "ordinary exception stack";
		final privateStack = try throw @:privateAccess (Exception.thrown("") : Exception) catch (e:Exception) e.stack;
		if (privateStack == null)
			throw "private exception stack";
		final map = {
			var x:TypedefToStringMap<String> = new TypedefToStringMap<String>();
			x;
		};
		map.set("key", "value");
		if (map.get("key") != "value")
			throw "typed block local";
		final nested = {
			var test = {
				append("3");
				99;
			};
			test;
		};
		if (nested != 99 || effects != "3")
			throw "nested value order";
		final objectValue = {
			var obj = {value: 1};
			obj.value;
		};
		if (objectValue != 1)
			throw "object literal";
		final conditional = {
			append("1");
			if (cond2(getInt())) {
				append("2");
			} else {
				append("3");
			}
			effects;
		};
		if (conditional != "31gc2")
			throw "conditional value order";
		final change:Link = {value: 1, next: {value: 2, next: null}};
		var last = 0;
		final walk = function():Void {
			var next = change;
			while (next.next != null) {
				next = next.next;
				last = next.value;
			}
		};
		walk();
		if (last != 2)
			throw "terminal loop";
		final commented = {
			var value:Int = 7;
			value;
		} /** trailing documentation */;
		if (commented != 7)
			throw "trailing comment";
	}
}
