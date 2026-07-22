package hxhx;

/** Request-local measurements from dependency observation mode. **/
class CompilationServerDependencyReport {
	public var enabled(default, null):Bool;
	public var hasPrevious(default, null):Bool;
	public var moduleCount(default, null):Int;
	public var edgeCount(default, null):Int;
	public var snapshotFingerprint(default, null):String;
	public var comparison(default, null):Null<CompilerDependencyComparison>;

	public function new(enabled:Bool) {
		this.enabled = enabled;
		hasPrevious = false;
		moduleCount = 0;
		edgeCount = 0;
		snapshotFingerprint = "none";
		comparison = null;
	}

	public function record(snapshot:CompilerDependencySnapshot, previous:Null<CompilerDependencySnapshot>):Void {
		if (!enabled || snapshot == null)
			return;
		moduleCount = snapshot.getModules().length;
		edgeCount = snapshot.getEdges().length;
		snapshotFingerprint = CompilerObservationFingerprint.display(snapshot.getCanonicalIdentity());
		hasPrevious = previous != null;
		comparison = previous == null ? null : CompilerDependencyInvalidator.compare(previous, snapshot);
	}
}
