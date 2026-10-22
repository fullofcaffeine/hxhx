abstract Counter(Int) from Int to Int {
	public inline function bump(amount:Int):Int {
		this = this + amount;
		return this;
	}

	public inline function conditional(amount:Int):Int {
		if (amount < 0)
			return this;
		this = this + amount;
		return this;
	}

	public inline function fail(amount:Int):Int {
		this = this + amount;
		throw "stop";
	}

	public inline function twice(amount:Int):Int {
		this = this + amount;
		this = this + amount;
		return this;
	}

	public inline function ignore(amount:Int):Int {
		return this;
	}
}

class Holder {
	public var value:Counter = 10;

	public function new() {}
}

class Main {
	static function output<T>(value:T):Void {
		#if js
		haxe.Log.trace(value, null);
		#else
		Sys.println(value);
		#end
	}

	static var events = "";
	static var holder = new Holder();
	static var values:Array<Counter> = [20];

	static function receiver():Holder {
		events += "receiver;";
		return holder;
	}

	static function array():Array<Counter> {
		events += "array;";
		return values;
	}

	static function index():Int {
		events += "index;";
		return 0;
	}

	static function argument():Int {
		events += "argument;";
		return 3;
	}

	static function failingArgument():Int {
		events += "argument-throw;";
		throw "argument-stop";
	}

	static function main():Void {
		var result = receiver().value.bump(argument());
		output(events);
		output(result);
		output((holder.value : Int));
		events = "";
		result = array()[index()].bump(argument());
		output(events);
		output(result);
		output((values[0] : Int));
		var local:Counter = 30;
		result = local.bump({local = 40; 2;});
		output(result);
		output((local : Int));
		result = local.conditional(-1);
		output(result);
		output((local : Int));
		result = local.conditional(1);
		output(result);
		output((local : Int));
		try {
			local.fail(2);
		} catch (error:String) {
			output(error);
		}
		output((local : Int));
		local = 2;
		output(local.twice((local : Int)));
		output((local : Int));
		events = "";
		output(local.ignore(argument()));
		output(events);
		events = "";
		try {
			receiver().value.bump(failingArgument());
		} catch (error:String) {
			output(error);
		}
		output(events);
		output((holder.value : Int));
	}
}
