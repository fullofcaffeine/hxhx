/**
	Seed value used by the Serializer/Unserializer oracle runner.
**/
class Box {
	public var count:Int;
	public var label:String;

	public function new(count:Int, label:String) {
		this.count = count;
		this.label = label;
	}
}

/**
	Seed enum used to pin constructor and argument round trips.
**/
enum SeedEnum {
	A;
	With(value:Int, label:String);
}

/**
	Repo-owned upstream Haxe oracle cases for Serializer/Unserializer behavior.

	Case IDs intentionally match
	`docs/00-project/SERIALIZER_UNSERIALIZER_BEHAVIOR_MATRIX.md` so follow-up
	target lanes can record pass, unsupported_diagnostic, or known_divergence
	against the same behavior surface.
**/
class Main {
	static function emit(id:String, field:String, value:String):Void {
		Sys.println(id + "|" + field + "|" + value);
	}

	static function roundTrip(id:String, value:Dynamic, summarize:Dynamic->String):Void {
		final serialized = haxe.Serializer.run(value);
		emit(id, "serialized", serialized);
		final decoded:Dynamic = haxe.Unserializer.run(serialized);
		emit(id, "decoded", summarize(decoded));
	}

	static function roundTripIndexedEnum(id:String, value:Dynamic, summarize:Dynamic->String):Void {
		final previous = haxe.Serializer.USE_ENUM_INDEX;
		haxe.Serializer.USE_ENUM_INDEX = true;
		final serialized = haxe.Serializer.run(value);
		haxe.Serializer.USE_ENUM_INDEX = previous;
		emit(id, "serialized", serialized);
		final decoded:Dynamic = haxe.Unserializer.run(serialized);
		emit(id, "decoded", summarize(decoded));
	}

	static function invalid(id:String, input:String):Void {
		emit(id, "input", input);
		try {
			final decoded:Dynamic = haxe.Unserializer.run(input);
			emit(id, "result", "value:" + Std.string(decoded));
		} catch (e:Dynamic) {
			emit(id, "error", Std.string(e));
		}
	}

	static function main():Void {
		roundTrip("ser-null-bool-01:null", null, function(v) return Std.string(v == null));
		roundTrip("ser-null-bool-01:true", true, function(v) return Std.string(v));
		roundTrip("ser-null-bool-01:false", false, function(v) return Std.string(v));
		roundTrip("ser-int-01:positive", 7, function(v) return Std.string(v));
		roundTrip("ser-int-01:negative", -3, function(v) return Std.string(v));
		roundTrip("ser-float-01:finite", 3.5, function(v) return Std.string(v));
		roundTrip("ser-string-01:unicode", "hxhx é\\n", function(v) return Std.string(v.length) + ":" + v);
		roundTrip("ser-array-01:mixed", [1, null, "x"], function(v) {
			final a:Array<Dynamic> = cast v;
			return Std.string(a.length) + ":" + Std.string(a[1] == null) + ":" + Std.string(a[2]);
		});
		roundTrip("ser-anon-01:fields", {
			name: "hxhx",
			count: 3,
			enabled: true
		}, function(v) {
			return Std.string(Reflect.field(v, "name"))
				+ ":"
				+ Std.string(Reflect.field(v, "count"))
				+ ":"
				+ Std.string(Reflect.field(v, "enabled"));
		});
		roundTrip("ser-class-01:box", new Box(5, "five"), function(v) {
			return Std.string(Std.isOfType(v, Box)) + ":" + v.label + ":" + Std.string(v.count);
		});
		roundTrip("ser-enum-01:zero", SeedEnum.A, function(v) {
			return Type.enumConstructor(v) + ":" + Std.string(Type.enumParameters(v).length);
		});
		roundTrip("ser-enum-01:args", SeedEnum.With(9, "nine"), function(v) {
			return Type.enumConstructor(v) + ":" + Type.enumParameters(v).join(",");
		});
		roundTripIndexedEnum("ser-enum-index-01:zero", SeedEnum.A, function(v) {
			return Type.enumConstructor(v) + ":" + Std.string(Type.enumParameters(v).length);
		});
		roundTripIndexedEnum("ser-enum-index-01:args", SeedEnum.With(4, "four"), function(v) {
			return Type.enumConstructor(v) + ":" + Type.enumParameters(v).join(",");
		});
		roundTrip("ser-bytes-01:ascii", haxe.io.Bytes.ofString("ABC"), function(v) {
			final b:haxe.io.Bytes = cast v;
			return Std.string(b.length) + ":" + b.toString();
		});
		invalid("ser-error-01:invalid-token", "!");
		invalid("ser-error-01:truncated-object", "o");
	}
}
