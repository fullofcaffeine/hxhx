package hxhx;

/**
	Protocol-neutral result from one compiler-server request.

	Transport adapters decide how to frame this result. They send every response
	before acting on a successful, cleaned-up request to stop the server.
**/
class CompilationServerReply {
	final outputEvents:Array<CompilationRequestOutputEvent>;

	public final isError:Bool;
	public final stopServer:Bool;

	public function new(outputEvents:Array<CompilationRequestOutputEvent>, isError:Bool, stopServer:Bool = false) {
		this.outputEvents = outputEvents.copy();
		this.isError = isError;
		this.stopServer = stopServer;
	}

	public static function message(text:String, isError:Bool, stopServer:Bool = false):CompilationServerReply {
		return new CompilationServerReply([new CompilationRequestOutputEvent(text + "\n", true)], isError, stopServer);
	}

	public function events():Array<CompilationRequestOutputEvent> {
		return outputEvents.copy();
	}
}
