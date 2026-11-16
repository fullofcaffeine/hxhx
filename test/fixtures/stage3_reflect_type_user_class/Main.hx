import tools.Reflect;

/**
	`Reflect` here is the project class `tools.Reflect`, not the standard one.
	Its calls must run the project's methods.
**/
class Main {
	static function main() {
		Sys.println(Reflect.hasField({a: 1}, "a"));
		Sys.println(Reflect.isFunction(main));
		Sys.println(std.Reflect.hasField({a: 1}, "a"));
	}
}
