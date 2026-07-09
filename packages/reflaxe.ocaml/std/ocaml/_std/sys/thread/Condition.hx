package sys.thread;

#if (!target.threaded)
#error "This class is not available on this target"
#end

/**
	OCaml-target `sys.thread.Condition` backed by `HxThread` runtime primitives.
**/
@:coreApi
class Condition {
	final handle:Int;

	public function new():Void {
		handle = NativeHxThread.condition_create();
	}

	public function acquire():Void {
		NativeHxThread.condition_acquire(handle);
	}

	public function tryAcquire():Bool {
		return NativeHxThread.condition_try_acquire(handle);
	}

	public function release():Void {
		NativeHxThread.condition_release(handle);
	}

	public function wait():Void {
		NativeHxThread.condition_wait(handle);
	}

	public function signal():Void {
		NativeHxThread.condition_signal(handle);
	}

	public function broadcast():Void {
		NativeHxThread.condition_broadcast(handle);
	}
}
