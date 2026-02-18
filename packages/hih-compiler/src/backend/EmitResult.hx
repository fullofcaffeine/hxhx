package backend;

/**
	Backend emission result returned to the Stage3 driver.

	Why
	- Different targets produce different artifact sets and may or may not run a build step.
	- The driver needs one stable contract so target-specific details stay inside backends.

	What
	- `entryPath`: primary artifact path for user-facing logs.
	- `artifacts`: all artifacts emitted by this backend invocation.
	- `builtExecutable`: true when a native/executable build step was performed.
**/
class EmitResult {
	public final entryPath:String;
	public final artifacts:Array<EmitArtifact>;
	public final builtExecutable:Bool;

	public function new(entryPath:String, artifacts:Array<EmitArtifact>, builtExecutable:Bool) {
		this.entryPath = entryPath == null ? "" : entryPath;
		this.artifacts = artifacts == null ? [] : artifacts;
		this.builtExecutable = builtExecutable;
	}
}

