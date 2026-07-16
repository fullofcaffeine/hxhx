/**
	One immutable typed module revision.

	Parsed declarations remain available for imports, metadata, diagnostics, and
	source provenance. Function-body semantics live in `typedClasses`; backends
	must not re-read bodies through `getParsed()`. A module is sealed at
	construction and rejects parsed-body mutation until it is retyped as a new
	revision.
**/
class TypedModule {
	final parsed:ParsedModule;
	final env:TyModuleEnv;
	final typedClasses:Array<TypedClass>;
	final revision:Int;
	final backendDeclaration:HxModuleDecl;

	public function new(parsed:ParsedModule, env:TyModuleEnv, ?typedClasses:Array<TypedClass>, revision:Int = 1) {
		this.parsed = parsed;
		this.env = env;
		this.typedClasses = (typedClasses == null ? TypedBodyBuilder.buildFallbackModule(parsed, env) : typedClasses).copy();
		this.revision = revision <= 0 ? 1 : revision;
		TypedBodyInvariant.assertClasses(this.typedClasses);
		this.backendDeclaration = TypedBodySource.moduleDeclaration(parsed, this.typedClasses);
	}

	public function getParsed():ParsedModule {
		return parsed;
	}

	public function getEnv():TyModuleEnv {
		return env;
	}

	public function getTypedClasses():Array<TypedClass> {
		return typedClasses.copy();
	}

	public function getRevision():Int {
		return revision;
	}

	/**
		Return the declaration/signature projection whose bodies come exclusively
		from the structural typed tree.

		This is the one-cutover adapter for source-shaped emitters. It must not be
		used by typing or macros, and it never re-reads parsed function bodies. The
		legacy source AST uses mutable arrays, so backends must treat this cached
		projection as read-only; it is not semantic storage and cannot mutate the
		structural typed body.
	**/
	public function getBackendDeclaration():HxModuleDecl {
		return backendDeclaration;
	}

	/** Revalidate the sealed syntax revision before macro/backend consumption. **/
	public function assertBodyRevisionCurrent():Void {
		TypedBodyInvariant.assertClasses(typedClasses);
		for (typedClass in typedClasses)
			for (typedFunction in typedClass.getFunctions())
				typedFunction.assertParsedBodyCurrent();
	}
}
