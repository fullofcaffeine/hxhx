package hxhx;

/**
	Final and working filesystem paths for one compiler request.

	A direct command uses the same path for both views. A server request writes
	to `working*` paths owned by `CompilationRequestOutputTransaction`; after a
	successful publish, diagnostics and returned artifacts use the `final*` paths
	the client originally requested.
**/
class CompilationRequestOutputPaths {
	public final finalOutDir:String;
	public final workingOutDir:String;
	public final finalBackendOutputDir:String;
	public final workingBackendOutputDir:String;
	public final finalOutputFileHint:Null<String>;
	public final workingOutputFileHint:Null<String>;

	public function new(finalOutDir:String, workingOutDir:String, finalBackendOutputDir:String, workingBackendOutputDir:String,
			finalOutputFileHint:Null<String>, workingOutputFileHint:Null<String>) {
		this.finalOutDir = finalOutDir;
		this.workingOutDir = workingOutDir;
		this.finalBackendOutputDir = finalBackendOutputDir;
		this.workingBackendOutputDir = workingBackendOutputDir;
		this.finalOutputFileHint = finalOutputFileHint;
		this.workingOutputFileHint = workingOutputFileHint;
	}

	public static function direct(outDir:String, backendOutputDir:String, outputFileHint:Null<String>):CompilationRequestOutputPaths {
		return new CompilationRequestOutputPaths(outDir, outDir, backendOutputDir, backendOutputDir, outputFileHint, outputFileHint);
	}
}
