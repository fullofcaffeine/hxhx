/** Stored methods retain receiver identity and observe subsequent field mutations. */
class Main {
	static var evaluations:Int = 0;

	static function create():Counter {
		evaluations++;
		return new Counter(11);
	}

	static function main():Void {
		final counter = new Counter(7);
		final read = counter.read;
		Sys.println(read());
		counter.value = 9;
		Sys.println(read());
		Sys.println(read == counter.read);
		Sys.println(read == counter.other);
		Sys.println(read == new Counter(9).read);
		final temporary = create().read;
		Sys.println(temporary());
		Sys.println(evaluations);
		final add = counter.add;
		Sys.println(add(3));
		Sys.println(add());
		final child = new Child(20);
		final base:Counter = child;
		final overridden = base.read;
		Sys.println(overridden());
		Sys.println(overridden == child.read);
		final box = new Box<String>("kept");
		final get = box.get;
		Sys.println(get());
		box.value = "changed";
		Sys.println(get());
		final numbers = new Box<Int>(17);
		final number = numbers.get;
		Sys.println(number());
		numbers.value = 19;
		Sys.println(number());
		final nullable = new Box<Null<Int>>(null);
		final empty = nullable.get;
		Sys.println(empty() == null);
		final nested = function():Int {
			final selected = counter.read;
			return selected();
		};
		Sys.println(nested());
		Sys.println(new Holder().reader());
	}
}

/** An ordinary receiver, with optional argument transport and two distinct method identities. */
class Counter {
	public var value:Int;

	public function new(value:Int)
		this.value = value;

	public function read():Int
		return value;

	public function other():Int
		return value;

	public function add(amount:Int = 2):Int
		return value + amount;
}

/** A stored Base method must select the same override as an ordinary virtual call. */
class Child extends Counter {
	public function new(value:Int)
		super(value);

	override public function read():Int
		return value + 1;
}

/** The receiver application determines the stored callable's concrete result. */
class Box<T> {
	public var value:T;

	public function new(value:T)
		this.value = value;

	public function get():T
		return value;
}

/** Instance initialization owns the method value before the constructor body runs. */
class Holder {
	public var reader:Void->Int = new Counter(30).read;

	public function new() {}
}
