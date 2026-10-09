import providers.Api as Chosen;

using providers.Api;

/** Observe qualified calls, aliases, package ownership, and argument order. */
class Main {
	static function argument(value:String):String {
		Sys.println(value);
		return value;
	}

	static function main():Void {
		Sys.println(providers.Api.combine(argument("left"), argument("right")));
		Sys.println(other.Api.combine("a", "b"));
		Sys.println(Chosen.combine("alias", "call"));
		Sys.println(providers.Api.repeat(3));
		Sys.println(providers.Api.shadow());
		Sys.println("value".decorate());
		Sys.println(providers.Api.nullable(null));
		Sys.println(Switchboard.word());
		Switchboard.word = function():String return "after";
		Sys.println(Switchboard.word());
		var providers = {Api: {combine: function(left:String, right:String):String return "local:" + left + ":" + right}};
		Sys.println(providers.Api.combine("x", "y"));
		var Chosen = {combine: function(left:String, right:String):String return "chosen-local:" + left + ":" + right};
		Sys.println(Chosen.combine("u", "v"));
	}
}

/** Dynamic static calls must read the current function after reassignment. */
class Switchboard {
	public static dynamic function word():String {
		return "before";
	}
}
