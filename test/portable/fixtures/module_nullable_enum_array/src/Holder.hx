/** Connects the producer and collector through a recursive module dependency. */
class Holder {
	public final value:Null<Choice>;
	public var reads:Int = 0;

	public function new(value:Null<Choice>)
		this.value = value;

	public function collect(out:Array<Choice>):Void
		Collector.collect(read(), out);

	function read():Null<Choice> {
		reads++;
		return value;
	}
}
