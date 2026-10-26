import NoPrimaryFunctions.Secondary;

/** An explicit secondary type import does not expose its module's functions. */
class SecondaryTypeMain {
	static function main():Void
		moduleOnly();
}
