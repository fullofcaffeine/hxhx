/**
	Stage 3 typer error (structured, position-aware).

	Why
	- Gate 1 bring-up needs failures to be actionable: `file:line:col` is the
	  baseline ergonomics required to iterate quickly.
	- A dedicated error type makes it easy for Stage3/Stage4 runners to format
	  messages deterministically (and eventually to attach richer diagnostics).

	What
	- Carries:
	  - `filePath`: best-effort path of the module being typed
	  - `pos`: statement-level position (line/col/index)
	  - `message`: human-facing description

	How
	- We keep this as a tiny data class rather than depending on target-specific
	  exception base classes. Stages can `throw new TyperError(...)` and rely on
	  `toString()` being stable across targets.
**/
class TyperError {
	public final filePath:String;
	public final pos:HxPos;
	public final message:String;

	public function new(filePath:String, pos:HxPos, message:String) {
		this.filePath = (filePath == null || filePath.length == 0) ? "<unknown>" : filePath;
		this.pos = pos == null ? HxPos.unknown() : pos;
		this.message = message == null ? "<no message>" : message;
	}

	public function toString():String {
		// `file:line:col: message`
		return filePath + ":" + pos.line + ":" + pos.column + ": " + message;
	}
}

