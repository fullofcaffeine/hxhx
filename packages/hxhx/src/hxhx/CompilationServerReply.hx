package hxhx;

/**
	Protocol-neutral result from one compiler-server request.

	Transport adapters decide how to frame this result. They do not reinterpret
	whether the compiler request succeeded or failed.
**/
class CompilationServerReply {
	final outputEvents:Array<CompilationRequestOutputEvent>;

	public final isError:Bool;

	public function new(outputEvents:Array<CompilationRequestOutputEvent>, isError:Bool) {
		this.outputEvents = outputEvents.copy();
		this.isError = isError;
	}

	public static function message(text:String, isError:Bool):CompilationServerReply {
		return new CompilationServerReply([new CompilationRequestOutputEvent(text + "\n", true)], isError);
	}

	public function events():Array<CompilationRequestOutputEvent> {
		return outputEvents.copy();
	}
}
