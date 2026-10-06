/** Independent class identity and final-field initialization through an ordinary constructor. */
class Box {
	public final id:Int;
	public var label:String;

	public function new(id:Int, label:String) {
		this.id = id;
		this.label = label;
	}
}

/** Both object arguments must survive allocation and become traced instance fields. */
class Pair {
	public final left:Box;
	public final right:Box;

	public function new(left:Box, right:Box) {
		this.left = left;
		this.right = right;
	}
}

/** A same-named field must still select this declaration and its own instance layout. */
class Other {
	public final id:Int;

	public function new(id:Int) {
		this.id = id;
	}
}

/** Ordinary source construction, initialization, lexical closure ownership, and field effects. */
class Main {
	static var events:String = '';
	static var seed:Box = new Box(90, 'seed');

	static function mark(value:Int):Int {
		events += '' + value;
		return value;
	}

	static function select(pair:Pair):Pair {
		events += 'r';
		return pair;
	}

	static function word():String {
		events += 'w';
		return 'changed';
	}

	static function overwrite(box:Box):String {
		box.label = 'replaced';
		return '!';
	}

	static function main():Void {
		final pair = new Pair(new Box(mark(1), 'left'), new Box(mark(2), 'right'));
		Sys.println(events);
		Sys.println(pair.left.id);
		Sys.println(pair.right.label);
		select(pair).left.label = word();
		Sys.println(events);
		Sys.println(pair.left.label);
		Sys.println(seed.id);
		final build = function(value:Int):Box {
			return new Box(value, 'closure');
		};
		final third = build(7);
		Sys.println(third.id);
		final other = new Other(5);
		Sys.println(other.id);
		Sys.println(pair.left.label += overwrite(pair.left));
		var local = 'local';
		Sys.println(local += 2);
	}
}
