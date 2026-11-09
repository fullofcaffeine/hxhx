import Shapes;

/** `null` fixes only nullability, so the parameter stays open. */
class GenericNullArgument {
	static function main():Void {
		new Pair2(null);
	}
}
