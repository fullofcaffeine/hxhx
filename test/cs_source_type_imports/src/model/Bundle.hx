package model;

/** Owns the secondary type's Haxe module identity. */
class Bundle {}

/** C# emits this class in the package, rather than a namespace named after Bundle. */
class Secondary {
	public function new() {}

	public static function visitSecondary():Void {}
}
