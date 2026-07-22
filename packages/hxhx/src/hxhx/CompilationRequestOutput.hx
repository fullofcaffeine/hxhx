package hxhx;

/**
	Owns the ordered output produced by one compiler request.

	Direct command-line compilations write immediately to the process streams.
	Server requests retain copied events so the transport can return them to the
	correct client after compilation. Closing the owner rejects later writes,
	which turns request-state leaks into deterministic failures.
**/
class CompilationRequestOutput {
	final buffered:Bool;
	final captured:Array<CompilationRequestOutputEvent>;
	var closed:Bool;

	public function new(buffered:Bool) {
		this.buffered = buffered;
		this.captured = [];
		this.closed = false;
	}

	public function stdoutLine(text:String):Void {
		write(text, false, true);
	}

	public function stderrLine(text:String):Void {
		write(text, true, true);
	}

	public static function writeStdoutLine(output:Null<CompilationRequestOutput>, text:String):Void {
		if (output == null)
			Sys.println(text);
		else
			output.stdoutLine(text);
	}

	public static function writeStderrLine(output:Null<CompilationRequestOutput>, text:String):Void {
		if (output == null) {
			final stream = Sys.stderr();
			stream.writeString(text + "\n");
			stream.flush();
		} else {
			output.stderrLine(text);
		}
	}

	public function events():Array<CompilationRequestOutputEvent> {
		return captured.copy();
	}

	public function close():Void {
		closed = true;
	}

	function write(text:String, isErrorStream:Bool, newline:Bool):Void {
		if (closed)
			throw "compiler request output is already closed";
		final value = text == null ? "null" : text;
		if (buffered) {
			captured.push(new CompilationRequestOutputEvent(value + (newline ? "\n" : ""), isErrorStream));
			return;
		}
		if (isErrorStream) {
			final stream = Sys.stderr();
			stream.writeString(value);
			if (newline)
				stream.writeString("\n");
			stream.flush();
		} else if (newline) {
			Sys.println(value);
		} else {
			Sys.print(value);
		}
	}
}
