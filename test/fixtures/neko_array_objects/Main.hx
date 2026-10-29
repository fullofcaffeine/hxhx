/** Array identity, logical length, iteration, patterns, and native storage agree. */
class Main {
	static function main():Void {
		final values = [2, 3];
		final alias = values;
		Sys.println(Type.getClass(values) == Array);
		Sys.println(Std.isOfType(values, Array));
		Sys.println(Type.getClass(neko.NativeArray.alloc(2)) == null);
		Sys.println(Std.isOfType(neko.NativeArray.alloc(2), Array));
		values[4] = 9;
		Sys.println(alias.length);
		Sys.println(alias[4]);
		Sys.println(values[3] == null);
		Sys.println(values.pop());
		values.resize(2);
		var sum = 0;
		for (value in values)
			sum += value;
		Sys.println(sum);
		var weighted = 0;
		for (key => value in values)
			weighted += (key + 1) * value;
		Sys.println(weighted);
		final mapped = [for (value in values) if (value > 2) value * 4];
		Sys.println(mapped.length);
		Sys.println(mapped[0]);
		Sys.println(Type.getClass(mapped) == Array);
		Sys.println(switch values {
			case [a, b]: a * 10 + b;
			case _: -1;
		});
		Sys.println(switch values {
			case [a, b] if (a < b): a * 10 + b;
			case _: -1;
		});
		final native = neko.NativeArray.alloc(2);
		native[0] = 6;
		native[1] = 8;
		final wrapped = neko.NativeArray.toArray(native);
		Sys.println(Type.getClass(wrapped) == Array);
		Sys.println(wrapped.push(10));
		Sys.println(wrapped[2]);
		Sys.println(neko.NativeArray.length(native));
		Sys.println(neko.NativeArray.length(neko.NativeArray.ofArrayCopy(values)));
	}
}
