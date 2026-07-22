/** Stable report names for dependency-observation phases. **/
class CompilerDependencyPhaseTools {
	public static function name(phase:CompilerDependencyPhase):String {
		return switch (phase) {
			case ModuleResolution: "module-resolution";
			case SharedTyping: "shared-typing";
		};
	}
}
