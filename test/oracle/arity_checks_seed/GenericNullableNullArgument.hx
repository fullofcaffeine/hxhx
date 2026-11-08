import Shapes;

/** `null` for a `Null<T>` parameter says nothing about `T`. */
class GenericNullableNullArgument {
	static function main():Void {
		new NullablePair(null);
	}
}
