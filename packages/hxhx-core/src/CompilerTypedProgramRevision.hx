/**
	One exact in-memory revision for a sealed target-neutral typed program.

	The revision groups repeated type contributions by their semantic Haxe source
	module, reuses `CompilerTypedModuleRevision` conflict checks, and sorts the
	result before sealing it. It describes typed Haxe facts only. Dependency
	edges, request configuration, target lowering, generated target artifacts, and
	persistent cache digests have separate owners.
**/
class CompilerTypedProgramRevision {
	final macroMode:Bool;
	final modules:Array<CompilerTypedModuleRevision>;
	final canonicalIdentity:String;

	public function new(moduleContributions:Array<CompilerTypedModuleRevision>, macroMode:Bool) {
		this.macroMode = macroMode;
		final contributionsByModule = new haxe.ds.StringMap<Array<CompilerTypedModuleRevision>>();
		if (moduleContributions != null)
			for (contribution in moduleContributions) {
				if (contribution == null)
					throw "typed program revision contains a null module contribution";
				final existing = contributionsByModule.get(contribution.modulePath);
				if (existing == null)
					contributionsByModule.set(contribution.modulePath, [contribution]);
				else
					existing.push(contribution);
			}
		final modulePaths = [for (modulePath in contributionsByModule.keys()) modulePath];
		modulePaths.sort(compareText);
		modules = [
			for (modulePath in modulePaths)
				CompilerTypedModuleRevision.mergeContributions(modulePath, contributionsByModule.get(modulePath))
		];
		final facts = new Array<Null<String>>();
		facts.push("compiler-typed-program-revision-v1");
		facts.push(macroMode ? "macro" : "ordinary");
		facts.push(Std.string(modules.length));
		for (module in modules)
			facts.push(module.getCanonicalIdentity());
		canonicalIdentity = CompilerCacheIdentity.encode(facts);
	}

	/**
		Seal the exact module contributions after revalidating every typed body.

		External macro inputs are not cache keys here. Their generated declarations
		and resulting typed trees are already part of the module revisions; the
		dependency graph retains the separate observation inputs needed to decide
		when the program must be rebuilt.
	**/
	public static function fromTypedModules(typedModules:Array<TypedModule>, macroMode:Bool):CompilerTypedProgramRevision {
		final contributions = new Array<CompilerTypedModuleRevision>();
		if (typedModules != null)
			for (typedModule in typedModules) {
				if (typedModule == null)
					throw "typed program revision contains a null typed module";
				typedModule.assertBodyRevisionCurrent();
				contributions.push(CompilerTypedModuleRevision.fromTypedModule(typedModule));
			}
		return new CompilerTypedProgramRevision(contributions, macroMode);
	}

	public function getMacroMode():Bool
		return macroMode;

	public function getModules():Array<CompilerTypedModuleRevision>
		return modules.copy();

	public function getCanonicalIdentity():String
		return canonicalIdentity;

	static function compareText(left:String, right:String):Int
		return left < right ? -1 : (left > right ? 1 : 0);
}
