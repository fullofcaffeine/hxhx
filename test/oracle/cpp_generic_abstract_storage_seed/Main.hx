/** Native scalar destinations convert generic null only after the generic body completes. */
class Main {
	public static var sawNull:Bool = false;

	static function main():Void {
		final integer = new Box<Int>(7, false);
		if (integer.read() != 7 || sawNull)
			throw "non-null Int constructor";
		final emptyInteger = new Box<Int>(7, true);
		if (!sawNull || emptyInteger.read() != 0 || emptyInteger.isNull())
			throw "concrete Int publication";
		final boolean = new Box<Bool>(true, false);
		if (!boolean.read() || sawNull)
			throw "non-null Bool constructor";
		final emptyBoolean = new Box<Bool>(true, true);
		if (!sawNull || emptyBoolean.read() || emptyBoolean.isNull())
			throw "concrete Bool publication";
		final text = new Box<String>("word", false);
		if (text.read() != "word" || sawNull)
			throw "non-null String constructor";
		final emptyText = new Box<String>("word", true);
		if (!sawNull || !emptyText.isNull())
			throw "String null publication";
		final generic = new Holder<Int>(7);
		if (!generic.isNull() || !generic.get().isNull())
			throw "generic abstract storage";
		final exact:Box<Int> = generic.get();
		if (exact.read() != 0 || exact.isNull())
			throw "concrete abstract destination";
		if (!generic.isNull())
			throw "conversion mutated source storage";
		final genericBool = new Holder<Bool>(true);
		final exactBool:Box<Bool> = genericBool.get();
		if (!genericBool.isNull() || exactBool.read() || exactBool.isNull())
			throw "Bool abstract destination";
		final abstractResult = new Empty<Box<Int>>();
		if (!abstractResult.get().isNull())
			throw "abstract type argument lost generic null";
		final concreteResult:Box<Int> = abstractResult.get();
		if (concreteResult.read() != 0 || concreteResult.isNull())
			throw "abstract type argument destination";
		final intResult = new Empty<Int>();
		final callback:() -> Int = function():Int {
			return intResult.get();
		};
		final concrete = new Concrete(callback);
		if (concrete.read() != 0)
			throw "non-generic callback receiver";
	}
}

/** The caller instantiates T with either a primitive or an abstract over that primitive. */
class Empty<T> {
	public function new() {}

	public function get():T
		return null;
}

/** Unlike Box<T>, this receiver selects Int storage inside its authored body. */
abstract Concrete(Int) {
	public function new(read:() -> Int)
		this = read();

	public function read():Int
		return this;
}

/** A field written with the enclosing binder keeps the generic abstract representation. */
class Holder<T> {
	final value:Box<T>;

	public function new(value:T)
		this.value = new Box<T>(value, true);

	public function get():Box<T>
		return value;

	public function isNull():Bool
		return value.isNull();
}

/** A captured callback exposes null while T is generic, including inside the constructor. */
abstract Box<T>(T) {
	public function new(value:T, empty:Bool) {
		var stored:T = value;
		final read:() -> T = function():T {
			if (empty)
				return null;
			return stored;
		};
		this = read();
		Main.sawNull = this == null;
	}

	public function read():T
		return this;

	public function isNull():Bool
		return this == null;
}
