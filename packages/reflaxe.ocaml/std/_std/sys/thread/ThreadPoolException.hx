package sys.thread;

import haxe.Exception;

/**
	Thread-pool contract exception for OCaml-target overrides.
**/
class ThreadPoolException extends Exception {
	public function new(message:String, ?previous:Exception) {
		super(message, previous);
	}
}
