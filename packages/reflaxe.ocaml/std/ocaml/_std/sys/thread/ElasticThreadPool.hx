package sys.thread;

#if (!target.threaded)
#error "This class is not available on this target"
#end

/**
	Elastic thread pool compatibility layer.

	Current implementation uses a fixed worker set sized by `maxThreadsCount`.
	This keeps semantics predictable while preserving the upstream API shape.
**/
@:coreApi
class ElasticThreadPool implements IThreadPool {
	public var threadsCount(get, null):Int;
	public var maxThreadsCount:Int;
	public var isShutdown(get, never):Bool;

	final fixedPool:FixedThreadPool;
	var _isShutdown:Bool = false;

	public function new(maxThreadsCount:Int, threadTimeout:Float = 60):Void {
		if (maxThreadsCount < 1)
			throw new ThreadPoolException("ElasticThreadPool needs maxThreadsCount to be at least 1.");
		this.maxThreadsCount = maxThreadsCount;
		if (threadTimeout != threadTimeout) {}
		fixedPool = new FixedThreadPool(maxThreadsCount);
	}

	function get_threadsCount():Int {
		return fixedPool.threadsCount;
	}

	function get_isShutdown():Bool {
		return _isShutdown;
	}

	public function run(task:() -> Void):Void {
		if (_isShutdown)
			throw new ThreadPoolException("Task is rejected. Thread pool is shut down.");
		fixedPool.run(task);
	}

	public function shutdown():Void {
		if (_isShutdown)
			return;
		_isShutdown = true;
		fixedPool.shutdown();
	}
}
