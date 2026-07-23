/**
	One sealed, target-neutral dependency observation for a complete typed request.

	The snapshot is immutable by convention: constructor inputs are copied and
	accessors return copies. Exact canonical identities are sorted before sealing,
	so equivalent compilations produce the same observation independent of map
	iteration order. Equivalent repeated observations of one logical module are
	coalesced. Two observations that reuse a module name but disagree on source,
	conditional-compilation choices, generated declarations, public interface, or implementation fail
	instead of silently overwriting one.
**/
class CompilerDependencySnapshot {
	final modules:Array<CompilerTypedModuleRevision>;
	final edges:Array<CompilerDependencyEdge>;
	final canonicalIdentity:String;

	public function new(modules:Array<CompilerTypedModuleRevision>, edges:Array<CompilerDependencyEdge>) {
		this.modules = normalizeModules(modules);
		this.edges = edges == null ? [] : edges.copy();
		this.edges.sort(compareEdges);
		canonicalIdentity = buildCanonicalIdentity(this.modules, this.edges);
	}

	public function getModules():Array<CompilerTypedModuleRevision>
		return modules.copy();

	public function getEdges():Array<CompilerDependencyEdge>
		return edges.copy();

	public function getCanonicalIdentity():String
		return canonicalIdentity;

	public function findModule(modulePath:String):Null<CompilerTypedModuleRevision> {
		for (module in modules)
			if (module.modulePath == modulePath)
				return module;
		return null;
	}

	static function buildCanonicalIdentity(modules:Array<CompilerTypedModuleRevision>, edges:Array<CompilerDependencyEdge>):String {
		final values = new Array<Null<String>>();
		values.push("compiler-dependency-snapshot-v4");
		values.push(Std.string(modules.length));
		for (module in modules) {
			values.push(module.modulePath);
			values.push(module.sourceRevision);
			values.push(module.sourceOriginRevision);
			values.push(module.sourceOriginDescription);
			values.push(module.conditionalCompilation.getCanonicalIdentity());
			values.push(module.generatedDeclarations.getCanonicalIdentity());
			values.push(module.publicInterfaceRevision);
			values.push(module.implementationRevision);
		}
		values.push(Std.string(edges.length));
		for (edge in edges)
			values.push(edge.canonicalKey());
		return CompilerCacheIdentity.encode(values);
	}

	static function compareModules(left:CompilerTypedModuleRevision, right:CompilerTypedModuleRevision):Int
		return compareText(left.modulePath, right.modulePath);

	static function normalizeModules(values:Array<CompilerTypedModuleRevision>):Array<CompilerTypedModuleRevision> {
		final sorted = values == null ? [] : values.copy();
		sorted.sort(compareModules);
		final out = new Array<CompilerTypedModuleRevision>();
		for (module in sorted) {
			if (module == null)
				throw "compiler dependency snapshot contains a null module revision";
			final previous = out.length == 0 ? null : out[out.length - 1];
			if (previous == null || previous.modulePath != module.modulePath) {
				out.push(module);
				continue;
			}
			final equivalent = previous.sourceRevision == module.sourceRevision
				&& previous.sourceOriginRevision == module.sourceOriginRevision
				&& previous.sourceOriginDescription == module.sourceOriginDescription
				&& previous.conditionalCompilation.getCanonicalIdentity() == module.conditionalCompilation.getCanonicalIdentity()
				&& previous.generatedDeclarations.getCanonicalIdentity() == module.generatedDeclarations.getCanonicalIdentity()
				&& previous.publicInterfaceRevision == module.publicInterfaceRevision
				&& previous.implementationRevision == module.implementationRevision;
			if (!equivalent)
				throw "compiler dependency snapshot contains conflicting observations for module identity: " + module.modulePath;
		}
		return out;
	}

	static function compareEdges(left:CompilerDependencyEdge, right:CompilerDependencyEdge):Int
		return compareText(left.canonicalKey(), right.canonicalKey());

	static function compareText(left:String, right:String):Int
		return left < right ? -1 : (left > right ? 1 : 0);
}
