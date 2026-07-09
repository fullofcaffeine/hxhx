package sys.thread;

#if (!target.threaded)
#error "This class is not available on this target"
#end

/**
	OCaml-target `sys.thread.Mutex` backed by `HxThread` runtime primitives.
**/
class Mutex {
	final handle:Int;

	public function new():Void {
		handle = NativeHxThread.mutex_create();
	}

	public function acquire():Void {
		NativeHxThread.mutex_acquire(handle);
	}

	public function tryAcquire():Bool {
		return NativeHxThread.mutex_try_acquire(handle);
	}

	public function release():Void {
		NativeHxThread.mutex_release(handle);
	}
}
