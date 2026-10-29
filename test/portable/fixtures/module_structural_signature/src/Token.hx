/** A richer record joins the recursive group without admitting array field optimizations. */
class Token {
	public final value:Int;
	public final values:Array<Int>;

	var linked:Null<Token>;

	public function new(value:Int) {
		this.value = value;
		this.values = [First.make(value).value];
		linked = null;
	}

	public function getLinked():Null<Token> {
		return linked;
	}

	public function setLinked(other:Null<Token>):Void {
		linked = other;
	}

	/** Omitted string arguments retain the backend's existing nullable string representation. */
	public function label(?fallback:String):Null<String> {
		return linked == null ? fallback : "linked";
	}

	public function getValues():Array<Int> {
		return values;
	}

	public function append(input:Array<Int>):Void {
		values.push(input[0]);
	}
}
