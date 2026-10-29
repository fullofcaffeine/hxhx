/** Observes base initialization and virtual calls on the allocated receiver. */
class Base {
	public var baseValue:Int = mark("base-field", 3);
	public var saved:Base;

	public function new(value:Int = 11) {
		Sys.println("base-body");
		baseValue = value;
		saved = this;
		Sys.println(describe());
	}

	public function describe():String {
		return "base";
	}

	public function setBase(__hxhx_self:Int):Void {
		baseValue = __hxhx_self;
	}

	public function identity():Base {
		return this;
	}

	public static function mark(label:String, value:Int):Int {
		Sys.println(label);
		return value;
	}
}
