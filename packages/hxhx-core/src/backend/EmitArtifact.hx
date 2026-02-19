package backend;

/**
	One backend output artifact.

	Why
	- Stage3 historically returned only one path (`out.exe`), which is too narrow for
	  multi-artifact targets such as JS (`.js` + optional `.map`).
	- A tiny artifact model lets the driver report outputs consistently without baking
	  OCaml assumptions into control flow.

	What
	- `kind`: semantic label (for example `entry_js`, `entry_executable`, `source_map`).
	- `path`: filesystem path to the emitted artifact.
**/
class EmitArtifact {
	public final kind:String;
	public final path:String;

	public function new(kind:String, path:String) {
		this.kind = kind == null ? "artifact" : kind;
		this.path = path == null ? "" : path;
	}
}

