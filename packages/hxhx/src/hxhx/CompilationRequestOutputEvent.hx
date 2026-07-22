package hxhx;

/**
	One ordered piece of text produced while handling a compiler request.

	The server keeps stdout and stderr distinct because Haxe clients display them
	differently. `text` contains the exact requested characters, including a final
	newline when the writer used a line-oriented method.
**/
class CompilationRequestOutputEvent {
	public final text:String;
	public final isErrorStream:Bool;

	public function new(text:String, isErrorStream:Bool) {
		this.text = text;
		this.isErrorStream = isErrorStream;
	}
}
