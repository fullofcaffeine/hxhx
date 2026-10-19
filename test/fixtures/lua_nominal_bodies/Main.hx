/** Observe constructor effects and receiver identity without target-specific APIs. */
class Main {
	static function main():Void {
		final left = new Child(4);
		final right = new Child(9);
		final bound = left.read;
		Sys.println(left.bounce());
		left.score = 6;
		Sys.println(bound());
		Sys.println(right.read());
		Sys.println(left.identity() == left);
		final values = [left, right];
		Sys.println(values[0].read());
		values[1] = left;
		Sys.println(values[1].read());
		new OrderedChild();
		Sys.println(new ReceiverNames(11).read());
		final captured = relay;
		Sys.println(captured(20));
		final callbacks:Array<() -> Void> = [];
		callbacks.push(function() {
			Sys.println(left.read());
		});
		callbacks[0]();
		Sys.println((function(value:Int) return value + 2)(5));
	}

	static function relay(value:Int):Int {
		return increment(value);
	}

	static function increment(value:Int):Int {
		return value + 1;
	}

	public static function mark(label:String):Int {
		Sys.println(label);
		return 1;
	}
}

/** The inherited constructor must initialize the receiver used by later methods. */
class Base {
	public var score:Int;

	public function new(score:Int) {
		this.score = score;
		Sys.println("construct:" + score);
	}

	public function read():Int {
		return score;
	}

	public function identity():Base {
		return this;
	}
}

/** Inherited storage and virtual calls must use the same instance. */
class Child extends Base {
	override public function read():Int {
		return score + 1;
	}

	public function bounce():Int {
		return read();
	}
}

/** Parent initializers execute when the explicit parent constructor is invoked. */
class OrderedBase {
	var baseValue = Main.mark("base-field");

	public function new() {
		Sys.println("base-body");
	}
}

/** Child initializers precede the child body, including effects before super. */
class OrderedChild extends OrderedBase {
	var childValue = Main.mark("child-field");

	public function new() {
		Sys.println("child-before-super");
		super();
		Sys.println("child-after-super");
	}
}

/** Authored names must not capture the generated receiver or class-table bindings. */
class ReceiverNames {
	var score:Int;

	public function new(self:Int) {
		this.score = self;
	}

	public function read():Int {
		final __hx_lua_classes = 1;
		final __hx_lua_receiver = 2;
		return this.score + __hx_lua_classes + __hx_lua_receiver;
	}
}
