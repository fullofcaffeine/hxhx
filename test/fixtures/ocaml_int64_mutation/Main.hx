/**
	Observe Int64 word mutation through aliases and copies.

	Haxe stores an Int64 as a reference to a two-word object. The private
	setters used by haxe.io.FPHelper change that object in place, so every alias
	sees the new words while a copy and any arithmetic result stay separate.
**/
class Main {
	static function receiver(value:haxe.Int64):haxe.Int64 {
		Sys.println("receiver");
		return value;
	}

	static function show(label:String, value:haxe.Int64):Void {
		Sys.println(label + " " + Std.string(value) + " " + value.high + " " + value.low);
	}

	static function main():Void {
		final original = haxe.Int64.ofInt(0);
		final alias = original;
		final separate = original.copy();
		@:privateAccess original.set_low(3);
		@:privateAccess original.set_high(4);
		show("original", original);
		show("alias", alias);
		show("separate", separate);

		final words = haxe.Int64.make(1, 2);
		Sys.println(@:privateAccess words.set_low(-1));
		Sys.println(@:privateAccess receiver(words).set_high(0x80000000));
		show("signed", words);

		final sum = words + 1;
		show("sum", sum);
		show("unchanged", words);

		final dynamicValue:Dynamic = original;
		Sys.println(haxe.Int64.isInt64(dynamicValue));
		Sys.println(haxe.Int64.isInt64(3));
	}
}
