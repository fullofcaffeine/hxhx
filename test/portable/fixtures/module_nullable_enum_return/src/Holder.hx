/** Stores an optional enum; the projection creates a recursive module dependency. */
class Holder {
	public final value:Null<Choice>;
	public var reads:Int = 0;

	public function new(value:Null<Choice>) {
		this.value = value;
	}

	public static function read(holder:Holder):Null<Choice> {
		holder.reads++;
		return holder.value;
	}

	public function project():Projection {
		return new Projection(this);
	}
}
