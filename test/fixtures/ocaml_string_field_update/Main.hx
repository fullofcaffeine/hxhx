/** Exercises ordinary String storage through implicit and explicit receivers. */
class Builder {
	public var text:String;

	public function new() {
		text = "";
	}

	public function add<T>(value:T):Void {
		text += value;
	}

	public function addString(value:String):Void {
		text += value;
	}

	public function addInt(value:Int):Void {
		text += value;
	}

	public function addBool(value:Bool):Void {
		text += value;
	}

	public function select():Builder {
		Sys.println("receiver");
		return this;
	}

	public function replace():String {
		Sys.println("right");
		text = "reset";
		return "R";
	}

	public function appendAndReturn(value:String):String {
		return this.text += value;
	}
}

/** Runtime output distinguishes missing writes, repeated effects, and wrong old-value capture. */
class Main {
	static function main():Void {
		final generic = new Builder();
		generic.add("a");
		generic.add(2);
		generic.add(true);
		Sys.println(generic.text);
		final concrete = new Builder();
		concrete.addString("a");
		concrete.addInt(2);
		concrete.addBool(true);
		Sys.println(concrete.text);
		final effects = new Builder();
		effects.text = "seed";
		Sys.println(effects.select().text += effects.replace());
		Sys.println(effects.text);
		Sys.println(effects.appendAndReturn("!"));
		Sys.println(effects.text);
	}
}
