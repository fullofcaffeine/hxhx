package hxhx;

/**
	Protocol-neutral result from one compiler-server request.

	Transport adapters decide how to frame this result. They do not reinterpret
	whether the compiler request succeeded or failed.
**/
class CompilationServerReply {
	public final payload:String;
	public final isError:Bool;

	public function new(payload:String, isError:Bool) {
		this.payload = payload;
		this.isError = isError;
	}
}
