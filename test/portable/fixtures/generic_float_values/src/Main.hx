class Holder<T> {
	public var value:T;

	public function new(value:T)
		this.value = value;
}

class Main {
	static function main() {
		final fromInt = new Holder<Float>(1);
		Sys.println("from int=" + fromInt.value * 2);
		final fromFloat = new Holder<Float>(1.5);
		Sys.println("from float=" + fromFloat.value * 2);
		final values:Array<Holder<Float>> = [new Holder<Float>(3), new Holder<Float>(0.25)];
		var sum = 0.0;
		for (holder in values)
			sum += holder.value;
		Sys.println("sum=" + sum);
	}
}
