/**
	One external file explicitly registered as an input to a macro-owned module.

	The request-local observer may use the resolved path and exact bytes to build
	this value, but the immutable record retains only SHA-256 revisions and a
	closed file-state label. This prevents server reports and long-lived
	dependency snapshots from exposing machine paths or file contents.
**/
class CompilerMacroFileDependencyInput {
	public static inline final FILE_STATE:String = "file";
	public static inline final MISSING_STATE:String = "missing";
	public static inline final NOT_FILE_STATE:String = "not-file";

	final pathIdentityRevision:String;
	final fileState:String;
	final contentRevision:String;
	final canonicalIdentity:String;

	private function new(pathIdentityRevision:String, fileState:String, contentRevision:String) {
		this.pathIdentityRevision = pathIdentityRevision == null ? "" : pathIdentityRevision;
		this.fileState = fileState == null ? "" : fileState;
		this.contentRevision = contentRevision == null ? "" : contentRevision;
		if (this.pathIdentityRevision.length == 0)
			throw "macro file dependency requires a path identity revision";
		if (this.fileState != FILE_STATE && this.fileState != MISSING_STATE && this.fileState != NOT_FILE_STATE)
			throw "macro file dependency has an unsupported file state";
		if (this.contentRevision.length == 0)
			throw "macro file dependency requires a content revision";
		canonicalIdentity = CompilerCacheIdentity.encode([
			"macro-file-dependency-input-v1",
			this.pathIdentityRevision,
			this.fileState,
			this.contentRevision
		]);
	}

	/**
		Hash a resolved request-local path and its observed state without retaining
		the path or bytes.
	**/
	public static function fromObservedPath(path:String, fileState:String, content:Null<haxe.io.Bytes>):CompilerMacroFileDependencyInput {
		final normalizedPath = haxe.io.Path.normalize(StringTools.replace(path == null ? "" : path, "\\", "/"));
		if (normalizedPath.length == 0)
			throw "macro file dependency requires a resolved path";
		if (fileState != FILE_STATE && fileState != MISSING_STATE && fileState != NOT_FILE_STATE)
			throw "macro file dependency has an unsupported file state";
		if (fileState == FILE_STATE && content == null)
			throw "macro file dependency file state requires exact bytes";
		if (fileState != FILE_STATE && content != null)
			throw "macro file dependency non-file state cannot retain bytes";
		final pathRevision = haxe.crypto.Sha256.encode(CompilerCacheIdentity.encode(["macro-file-dependency-path-v1", normalizedPath]));
		final contentRevision = content == null ? haxe.crypto.Sha256.encode(CompilerCacheIdentity.encode(["macro-file-dependency-content-v1", fileState])) : haxe.crypto.Sha256.make(content)
			.toHex()
			.toLowerCase();
		return new CompilerMacroFileDependencyInput(pathRevision, fileState, contentRevision);
	}

	public function getPathIdentityRevision():String
		return pathIdentityRevision;

	public function getCanonicalIdentity():String
		return canonicalIdentity;
}
