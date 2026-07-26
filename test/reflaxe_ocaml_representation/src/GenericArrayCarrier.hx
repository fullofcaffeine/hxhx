/**
	Exposes a generic `Array<T>` field so the representation fixture can prove
	that an unresolved element type is not guessed to be exact `Int`.
**/
class GenericArrayCarrier<T> {
	public var values:Array<T>;

	public function new(values:Array<T>) {
		this.values = values;
	}
}
