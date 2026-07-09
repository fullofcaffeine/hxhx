package sys.thread;

import haxe.Exception;

/**
	Thrown when a thread has no attached event loop.
**/
class NoEventLoopException extends Exception {
	public function new(message:String = "Event loop is not available for this thread.", ?previous:Exception) {
		super(message, previous);
	}
}
