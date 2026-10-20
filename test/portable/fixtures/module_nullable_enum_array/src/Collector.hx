/** Inserts only a selected non-null enum into its declared array element type. */
class Collector {
	public static function collect(value:Null<Choice>, out:Array<Choice>):Void {
		if (value == null)
			return;
		switch value {
			case Payload(_):
				out.push(value);
			case Empty:
		}
	}

	public static function from(holder:Holder, out:Array<Choice>):Void
		holder.collect(out);
}
