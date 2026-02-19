import Module;

/**
	Result of compiling a directory “project”.

	Why:
	- This is a class so field access stays in the class/record model (no
	  structural typing required).
**/
class CompileResult {
	public final stats:CompileStats;
	public final modules:Array<Module>;

	public function new(stats:CompileStats, modules:Array<Module>) {
		this.stats = stats;
		this.modules = modules;
	}
}
