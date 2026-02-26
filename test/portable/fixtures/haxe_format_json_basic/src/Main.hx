class Main {
	static function main() {
		final parsed = haxe.format.JsonParser.parse("{\"name\":\"hx\",\"nums\":[1,2,3],\"ok\":true}");
		final name:String = Reflect.field(parsed, "name");
		final nums:Array<Dynamic> = Reflect.field(parsed, "nums");
		final ok:Bool = Reflect.field(parsed, "ok");
		final sum = (cast nums[0] : Int) + (cast nums[1] : Int) + (cast nums[2] : Int);
		Sys.println("name=" + name);
		Sys.println("sum=" + sum);
		Sys.println("ok=" + ok);

		final encoded = haxe.format.JsonPrinter.print({answer: 42, text: "hello", flag: false});
		final reparsed = haxe.format.JsonParser.parse(encoded);
		Sys.println("answer=" + Reflect.field(reparsed, "answer"));
		Sys.println("text=" + Reflect.field(reparsed, "text"));
		Sys.println("flag=" + (Reflect.field(reparsed, "flag") == true));
	}
}
