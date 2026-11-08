/**
	`@:isVar` properties whose accessors read and write the physical field.

	Covers `(get, set)`, `(default, set)`, and `(null, set)` properties, a
	setter that ends with `return field = value`, writes from inside and
	outside the class, `++`, and compound assignment through the property.
	Each value is printed in its own statement, so the output does not depend
	on String concatenation operand order (Bead haxe_ocaml-b544p).
**/
class Settings {
	@:isVar public var level(get, set):Int = 1;
	@:isVar public var scale(default, set):Int = 10;
	@:isVar public var secret(null, set):Int = 20;

	public var log:Array<String> = [];

	public function new() {}

	function get_level():Int {
		return level;
	}

	function set_level(value:Int):Int {
		log.push("level=" + value);
		return level = value;
	}

	function set_scale(value:Int):Int {
		scale = value * 2;
		return scale;
	}

	function set_secret(value:Int):Int
		return secret = value + 1;

	public function readSecret():Int {
		return secret;
	}

	public function adjust():Void {
		level = 7;
		level++;
		level += 2;
		scale = 3;
		secret = 40;
	}
}

class Main {
	static function main():Void {
		final s = new Settings();
		s.level = 5;
		Sys.println("level: " + s.level);
		s.level++;
		Sys.println("level++: " + s.level);
		final before = s.level++;
		Sys.println("postfix value: " + before);
		final after = ++s.level;
		Sys.println("prefix value: " + after);
		s.level += 10;
		Sys.println("level +=: " + s.level);
		final assigned = (s.level = 3);
		Sys.println("assignment value: " + assigned);

		s.scale = 4;
		Sys.println("scale: " + s.scale);
		s.scale++;
		Sys.println("scale++: " + s.scale);
		s.scale *= 2;
		Sys.println("scale *=: " + s.scale);

		s.secret = 30;
		Sys.println("secret: " + s.readSecret());

		s.adjust();
		Sys.println("inside level: " + s.level);
		Sys.println("inside scale: " + s.scale);
		Sys.println("inside secret: " + s.readSecret());
		Sys.println("setter calls: " + s.log.join(","));
	}
}
