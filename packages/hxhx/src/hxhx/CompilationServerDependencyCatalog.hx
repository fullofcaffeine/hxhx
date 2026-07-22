package hxhx;

/**
	Long-lived owner of successful dependency observations for one wait server.

	Snapshots are grouped by the exact compiler argument list. This conservative
	identity may miss reuse opportunities, but it cannot combine two configurations
	merely because they share a main module. The catalog does not store or return
	typed modules; it only supports comparison reports before typed caching exists.

	The catalog retains a small, deterministic least-recently-published set of
	invocations. This bounds argument-variant growth while observation identities
	still contain large exact source and typed representations.
**/
class CompilationServerDependencyCatalog {
	static inline final DEFAULT_MAX_INVOCATIONS:Int = 8;

	final snapshotByInvocation:haxe.ds.StringMap<CompilerDependencySnapshot>;
	final invocationOrder:Array<String>;
	final maxInvocations:Int;

	public function new(?maxInvocations:Int) {
		snapshotByInvocation = new haxe.ds.StringMap<CompilerDependencySnapshot>();
		invocationOrder = [];
		this.maxInvocations = maxInvocations == null ? DEFAULT_MAX_INVOCATIONS : maxInvocations;
		if (this.maxInvocations <= 0)
			throw "dependency observation catalog requires a positive invocation limit";
	}

	public function openRequest(compilerArgs:Array<String>):CompilationServerDependencyRequest {
		final invocationIdentity = CompilerCacheIdentity.encode(["compiler-dependency-invocation-v1"].concat(compilerArgs == null ? [] : compilerArgs));
		final previous = snapshotByInvocation.get(invocationIdentity);
		if (previous != null)
			touch(invocationIdentity);
		return new CompilationServerDependencyRequest(invocationIdentity, previous, publish);
	}

	/** Discard observations without changing source/parser cache ownership. **/
	public function reset():Void {
		snapshotByInvocation.clear();
		invocationOrder.resize(0);
	}

	function publish(invocationIdentity:String, snapshot:CompilerDependencySnapshot):Void {
		snapshotByInvocation.set(invocationIdentity, snapshot);
		touch(invocationIdentity);
		while (invocationOrder.length > maxInvocations) {
			final evicted = invocationOrder.shift();
			if (evicted != null)
				snapshotByInvocation.remove(evicted);
		}
	}

	function touch(invocationIdentity:String):Void {
		invocationOrder.remove(invocationIdentity);
		invocationOrder.push(invocationIdentity);
	}
}
