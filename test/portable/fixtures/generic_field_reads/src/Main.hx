class Holder<T> {
	public var value:T;

	public function new(value:T)
		this.value = value;
}

class Pair<A, B> {
	public var first:A;
	public var second:B;

	public function new(first:A, second:B) {
		this.first = first;
		this.second = second;
	}
}

class Box {
	public var size:Int;

	public function new(size:Int)
		this.size = size;
}

class Main {
	static function main() {
		final number = new Holder<Int>(42);
		Sys.println("int=" + (number.value + 1));
		final ratio = new Holder<Float>(1.5);
		Sys.println("float=" + ratio.value * 2);
		final flag = new Holder<Bool>(true);
		Sys.println("bool=" + (flag.value ? "yes" : "no"));
		final text = new Holder<String>("hello");
		Sys.println("string=" + text.value.toUpperCase() + " length=" + text.value.length);
		final items = new Holder<Array<Int>>([1, 2, 3]);
		items.value.push(4);
		Sys.println("array=" + items.value.join(","));
		final step = new Holder<Int->Int>(x -> x * 10);
		Sys.println("function=" + step.value(4));
		final box = new Holder<Box>(new Box(7));
		Sys.println("class=" + box.value.size);
		final maybe = new Holder<Null<Bool>>(true);
		Sys.println("nullable bool=" + (maybe.value == true));
		final pair = new Pair<String, Int>("left", 2);
		Sys.println("pair=" + pair.first + ":" + (pair.second * 3));
	}
}
