package sys.thread;

#if (!target.threaded)
#error "This class is not available on this target"
#end

/**
	Fixed-size thread pool implementation for the OCaml portable lane.
**/
@:coreApi
class FixedThreadPool implements IThreadPool {
	public var threadsCount(get, null):Int;
	public var isShutdown(get, never):Bool;

	final workerCount:Int;
	final queue = new Deque<Null<() -> Void>>();
	var _isShutdown:Bool = false;

	public function new(threadsCount:Int):Void {
		if (threadsCount < 1)
			throw new ThreadPoolException("FixedThreadPool needs threadsCount to be at least 1.");
		this.workerCount = threadsCount;
		for (_ in 0...threadsCount) {
			Thread.create(workerLoop);
		}
	}

	static function invokeTask(task:() -> Void):Void {
		Reflect.callMethod(null, cast task, []);
	}

	function get_threadsCount():Int {
		return workerCount;
	}

	function get_isShutdown():Bool {
		return _isShutdown;
	}

	function workerLoop():Void {
		while (true) {
			final task = queue.pop(true);
			if (task == null)
				return;
			invokeTask(task);
		}
	}

	public function run(task:() -> Void):Void {
		if (_isShutdown)
			throw new ThreadPoolException("Task is rejected. Thread pool is shut down.");
		if (task == null)
			throw new ThreadPoolException("Task to run must not be null.");
		queue.add(task);
	}

	public function shutdown():Void {
		if (_isShutdown)
			return;
		_isShutdown = true;
		for (_ in 0...workerCount) {
			queue.add(null);
		}
	}
}
