package hxhx;

/**
	Stages one dependency snapshot for a single native server request.

	The request may compare against the last successful snapshot, but the result is
	observation only: typing still runs normally. Publication occurs only after the
	compiler request and its output transaction succeed.
**/
class CompilationServerDependencyRequest {
	final invocationIdentity:String;
	final previousSnapshot:Null<CompilerDependencySnapshot>;
	final publishCallback:(invocationIdentity:String, snapshot:CompilerDependencySnapshot) -> Void;
	final reportState:CompilationServerDependencyReport;
	var stagedSnapshot:Null<CompilerDependencySnapshot>;
	var snapshotRequired:Bool;
	var preparedForSuccess:Bool;
	var finished:Bool;

	public function new(invocationIdentity:String, previousSnapshot:Null<CompilerDependencySnapshot>,
			publish:(invocationIdentity:String, snapshot:CompilerDependencySnapshot) -> Void) {
		this.invocationIdentity = invocationIdentity;
		this.previousSnapshot = previousSnapshot;
		publishCallback = publish;
		reportState = new CompilationServerDependencyReport(true);
		stagedSnapshot = null;
		snapshotRequired = false;
		preparedForSuccess = false;
		finished = false;
	}

	/** Mark that this request entered ordinary compilation and must record its complete typed program. **/
	public function requireSnapshot():Void {
		ensureOpen();
		snapshotRequired = true;
	}

	/** Record the one complete typed-program observation produced by this request. **/
	public function record(snapshot:CompilerDependencySnapshot):Void {
		ensureOpen();
		if (snapshot == null)
			throw "dependency observation cannot record a null snapshot";
		if (stagedSnapshot != null)
			throw "dependency observation already recorded a typed program for this request";
		stagedSnapshot = snapshot;
		reportState.record(snapshot, previousSnapshot);
	}

	/** Validate the staged value before generated output becomes visible. **/
	public function prepareFinish(requestSucceeded:Bool):Void {
		ensureOpen();
		if (!requestSucceeded || preparedForSuccess)
			return;
		if (snapshotRequired && stagedSnapshot == null)
			throw "successful dependency observation request did not record the complete typed program";
		if (stagedSnapshot != null && stagedSnapshot.getCanonicalIdentity().length == 0)
			throw "dependency observation produced an empty snapshot identity";
		preparedForSuccess = true;
	}

	/** Publish after output succeeds, or discard every request-local value. **/
	public function finish(requestSucceeded:Bool):Void {
		if (finished)
			return;
		if (requestSucceeded) {
			prepareFinish(true);
			if (stagedSnapshot != null)
				publishCallback(invocationIdentity, stagedSnapshot);
		}
		stagedSnapshot = null;
		finished = true;
	}

	public function report():CompilationServerDependencyReport
		return reportState;

	function ensureOpen():Void {
		if (finished)
			throw "compiler dependency observation request is already closed";
	}
}
