package sys.thread;

#if (!target.threaded)
#error "This class is not available on this target"
#end

/**
	OCaml-target `sys.thread.Lock` backed by `HxThread` runtime primitives.
**/
class Lock {
	final handle:Int;

	public function new():Void {
		handle = NativeHxThread.lock_create();
	}

	public function wait(?timeout:Float):Bool {
		return timeout == null ? NativeHxThread.lock_wait(handle) : NativeHxThread.lock_wait_timeout(handle, timeout);
	}

	public function release():Void {
		NativeHxThread.lock_release(handle);
	}
}
