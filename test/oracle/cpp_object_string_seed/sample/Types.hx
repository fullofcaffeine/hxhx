package sample;

/** Native C++ uses declared short names for default instance conversion, including private types. */
class Types {
	public function new() {}

	public static function matches():Bool {
		return Std.string(new PublicName()) == "PublicName"
			&& Std.string(new PrivateName()) == "PrivateName"
			&& Std.string(new Types()) == "Types";
	}
}

/** A public secondary class must not print its source module or package path. */
class PublicName {
	public function new() {}
}

/** Its private lookup identity also remains separate from the native printed name. */
private class PrivateName {
	public function new() {}
}
