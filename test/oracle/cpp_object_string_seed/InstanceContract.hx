/** Independent assertions for ordinary instance conversion; the complete Main matrix remains required. */
class InstanceContract {
	public static var calls:Int = 0;

	static function require(value:Bool, label:String):Void {
		if (!value)
			throw label;
	}

	static function make():TextBox {
		calls++;
		return new TextBox("factory");
	}

	static function main():Void {
		require(Std.string(new PlainBox()) == "PlainBox", "plain name");
		require(sample.Types.matches(), "packaged names");
		final value = new TextBox("before");
		require(Std.string(value) == "before", "initial label");
		value.label = "after";
		require(Std.string(value) == "after", "mutated label");
		require(Std.string(new InheritedBox("inherited")) == "inherited", "inherited conversion");
		final base:TextBox = new OverrideBox("override");
		require(Std.string(base) == "child:override", "override conversion");
		require(Std.string(new NullBox()) == null, "null result");
		var failed = false;
		try {
			Std.string(new ThrowBox());
		} catch (message:String) {
			failed = message == "conversion failed";
		}
		require(failed, "conversion exception");
		require(Std.string(make()) == "factory", "factory conversion");
		require(calls == 9, "evaluation count");
		require(Std.string(new haxe.ValueException("wrapped")) == "wrapped", "wrapped exception");
		require(Std.string(new haxe.ValueException(new haxe.ValueException("nested"))) == "nested", "nested exception");
	}
}

/** A class without a custom conversion retains its ordinary runtime name. */
class PlainBox {
	public function new() {}
}

/** Allocation in user code must not invalidate the receiver passed to conversion. */
class TextBox {
	public var label:String;

	public function new(label:String)
		this.label = label;

	public function toString():String {
		InstanceContract.calls++;
		final pressure = [label, "temporary"];
		return pressure[0];
	}
}

/** An inherited method reads the actual object's current fields. */
class InheritedBox extends TextBox {
	public function new(label:String)
		super(label);
}

/** Standard conversion must select the override even through a base-typed source local. */
class OverrideBox extends TextBox {
	public function new(label:String)
		super(label);

	override public function toString():String {
		InstanceContract.calls++;
		return "child:" + super.toString();
	}
}

/** Native C++ preserves this null result; it is different from converting a null input. */
class NullBox {
	public function new() {}

	public function toString():String {
		InstanceContract.calls++;
		return null;
	}
}

/** A conversion failure propagates to the source catch without returning placeholder text. */
class ThrowBox {
	public function new() {}

	public function toString():String {
		InstanceContract.calls++;
		throw "conversion failed";
	}
}
