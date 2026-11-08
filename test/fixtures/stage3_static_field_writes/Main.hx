import counters.Item;
import counters.Registry;

/**
	Writes static fields in every assignment form and prints what each write stored.
	The same program runs under upstream Haxe and as a native OCaml executable.
**/
class Main {
	static var counter = 0;
	static var ratio:Float = 1.5;
	static var text = "x";
	static var flag = true;
	static var items:Array<String> = [];
	static var current:Item = new Item("first");
	static var maybe:Null<Item>;
	static var fromOther:Int = Registry.base + 1;
	static var seq:Int = counter + 5;
	static var transform:Int->Int = x -> x + 1;
	static var half:Null<Float>;

	/** The usual setter idiom: the parameter has the static's own name. */
	static function setRatio(ratio:Float):Void {
		Main.ratio = ratio;
	}

	/** A local named like a static shadows the bare name; the type path still names the static. */
	static function shadowed():Void {
		var counter = 3;
		counter++;
		Main.counter++;
		Sys.println(counter + " " + Main.counter);
		counter += 10;
		Main.counter += 100;
		Sys.println(counter + " " + Main.counter);
	}

	/** Writes used as operands: each update runs in source order and produces its Haxe value. */
	static function nested():Void {
		counter = 5;
		Sys.println(counter++ + counter++);
		Sys.println(++counter + ++counter);
		Sys.println(counter-- - --counter);
		counter = counter++ + ++counter;
		Sys.println(counter);
		ratio = 0.5;
		Sys.println((ratio += 1) + 1);
		Sys.println(ratio++ + 1);
		Sys.println(ratio);
	}

	/** Haxe divides Ints into a Float, so these values reach Float storage unchanged. */
	static function divisions():Void {
		counter = 3;
		ratio = 1 / 4;
		Sys.println(ratio);
		ratio = counter / 2;
		Sys.println(ratio);
		ratio += counter / 4;
		Sys.println(ratio);
		ratio = counter * 2 / 4;
		Sys.println(ratio);
		ratio = (counter + 1) * 1.125;
		Sys.println(ratio);
		text = "list ";
		final parts = [1, 2];
		text += parts;
		Sys.println(text);
		half = 1 / 2;
		Sys.println(half);
		var local:Float = 0.5;
		local = 1 / 4;
		Sys.println(local);
	}

	static function reset():Void {
		items = [];
		counter = 0;
		text = "reset";
	}

	static function main():Void {
		// Writes from inside the owning class through the bare name.
		counter++;
		++counter;
		counter += 3;
		counter -= 1;
		counter *= 2;
		Sys.println(counter);
		Sys.println(counter++);
		Sys.println(++counter);
		Sys.println(counter--);
		Sys.println(--counter);
		Sys.println(counter += 10);
		Sys.println(counter = 7);
		Sys.println(counter);
		ratio += 1;
		Sys.println(ratio);
		ratio = 2;
		ratio *= 1.25;
		Sys.println(ratio);
		Sys.println(++ratio);
		text += "y";
		text = text + "z";
		Sys.println(text);
		flag = !flag;
		Sys.println(flag);
		items.push("a");
		items = ["b", "c"];
		Main.items = Main.items.concat(["d"]);
		Sys.println(items.length + " " + items.join(","));
		current = new Item("second");
		Sys.println(current.name);
		Sys.println(maybe == null);
		maybe = current;
		Sys.println(maybe.name);

		// Qualified writes from inside the owning class.
		Main.counter = 100;
		Main.counter++;
		++Main.counter;
		Main.counter += 2;
		Sys.println(Main.counter);
		Sys.println(Main.counter++);
		Sys.println(counter);
		reset();
		Sys.println(items.length + " " + counter + " " + text);

		// A counter that closures update.
		final inc = () -> counter++;
		inc();
		inc();
		final add = (n:Int) -> {
			counter += n;
			return counter;
		};
		Sys.println(add(5));
		Sys.println(counter);

		// Startup order inside a module and across modules.
		Sys.println(fromOther + " " + seq + " " + Registry.doubled);

		// Writes to another module's statics, then reads from both modules.
		Registry.count++;
		++Registry.count;
		Registry.count += 5;
		Sys.println(Registry.count);
		Sys.println(Registry.bump());
		Sys.println(Registry.count++);
		Sys.println(Registry.count);
		Registry.total = 3;
		Registry.total += 0.25;
		Sys.println(Registry.total);
		Registry.setTotal(4);
		Registry.total -= 0.5;
		Sys.println(Registry.total);
		Registry.label = "changed";
		Registry.label += "!";
		Sys.println(Registry.label);
		Registry.enabled = true;
		Sys.println(Registry.enabled);
		Registry.names = Registry.names.concat(["b"]);
		Sys.println(Registry.report());
		Sys.println(Registry.last == null);
		Registry.last = new Item("z");
		Sys.println(Registry.last.name);
		Sys.println(Registry.pending == null);
		Registry.pending = 4;
		Sys.println(Registry.pending);
		Registry.pending++;
		Registry.pending += 2;
		Sys.println(Registry.pending);
		Registry.hit();
		Sys.println(Registry.hit());
		Sys.println(Registry.hits);

		// A helper class declared in this module, written from outside and from its own method.
		Holder.sf = 2;
		Holder.setStatic(3);
		Holder.sf += 0.25;
		Sys.println(Holder.sf);
		new Holder().addOne();
		Sys.println(Holder.sf);

		// Written statics read in loop, numeric, constructor, and call positions.
		while (counter < 9)
			counter++;
		Sys.println(counter * ratio);
		Sys.println(Registry.count * 0.5);
		Sys.println(new Item(text).name);
		Sys.println(transform(2));
		transform = x -> x * counter;
		Sys.println(transform(2));

		setRatio(0.75);
		Sys.println(ratio);
		shadowed();
		nested();
		divisions();
	}
}

/** A module-local class: its statics live in their own native module. */
class Holder {
	public static var sf:Float = 0.5;

	public function new() {}

	public static function setStatic(n:Int):Void {
		sf = n;
	}

	/** An instance method writes its class's static through the bare name. */
	public function addOne():Void {
		sf += 1;
	}
}
