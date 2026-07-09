package sys.thread;

#if (!target.threaded)
#error "This class is not available on this target"
#end

/**
	OCaml-target `sys.thread.Semaphore` backed by `HxThread` runtime primitives.
**/
@:coreApi
class Semaphore {
	final handle:Int;

	public function new(value:Int):Void {
		handle = NativeHxThread.semaphore_create(value);
	}

	public function acquire():Void {
		NativeHxThread.semaphore_acquire(handle);
	}

	public function tryAcquire(?timeout:Float):Bool {
		return timeout == null ? NativeHxThread.semaphore_try_acquire(handle) : NativeHxThread.semaphore_try_acquire_timeout(handle, timeout);
	}

	public function release():Void {
		NativeHxThread.semaphore_release(handle);
	}
}
