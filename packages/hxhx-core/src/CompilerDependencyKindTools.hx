/** Stable names and invalidation behavior for compiler dependency kinds. **/
class CompilerDependencyKindTools {
	public static function name(kind:CompilerDependencyKind):String {
		return switch (kind) {
			case ModuleResolution: "module-resolution";
			case PublicInterface: "public-interface";
			case InlineImplementation: "inline-implementation";
			case GeneratedDeclaration: "generated-declaration";
			case StaticInitialization: "static-initialization";
			case FeatureSelection: "feature-selection";
			case TargetNeutralProgram: "target-neutral-program";
		};
	}

	/** Whether a body-only provider change can invalidate this dependency. **/
	public static function consumesImplementation(kind:CompilerDependencyKind):Bool {
		return switch (kind) {
			case InlineImplementation: true;
			case GeneratedDeclaration: true;
			case StaticInitialization: true;
			case FeatureSelection: true;
			case TargetNeutralProgram: true;
			case ModuleResolution: false;
			case PublicInterface: false;
		};
	}
}
