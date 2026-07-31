/**
	Predicts affected modules from two clean dependency observations.

	Only modules whose own source or separately observed compiler input changed
	seed the prediction. This is important
	because the current observation is recorded after a clean full retype: a caller's
	typed output may already reflect its provider's change, but it must still be
	reached through a recorded edge instead of predicting itself.

	A compile-time condition change rechecks the module even when it selects the same
	parsed source. Reports name only the changed define keys, never their values.
	A changed build-macro result also rechecks the annotated module without retaining
	or reporting the generated member source.
	A changed file explicitly registered through `Context.registerModuleDependency`
	rechecks its owning module without retaining or reporting the file path or bytes.
	Public-interface changes propagate through every reverse dependency. A body-only
	change propagates only through edges that explicitly consume implementation,
	such as an inline call or an embeddable constant read. When a consumer's own
	public interface also changed, the stronger public change continues outward.
	A request-wide target or define change conservatively rechecks every current
	module. Finer feature, DCE, macro, and target-neutrality rules may later reduce
	that set after separate evidence exists. This mirrors the fixed-point shape a
	future typed-module cache needs while observation mode continues to type all
	modules normally.
	An input-only change rechecks the selected module but does not propagate when
	its public interface and implementation are byte-for-byte equivalent.
**/
class CompilerDependencyInvalidator {
	static inline final MODULE_INPUT_CHANGE:Int = 0;
	static inline final IMPLEMENTATION_CHANGE:Int = 1;
	static inline final PUBLIC_INTERFACE_CHANGE:Int = 2;

	public static function compare(previous:CompilerDependencySnapshot, current:CompilerDependencySnapshot):CompilerDependencyComparison {
		if (previous == null || current == null)
			throw "dependency invalidation comparison requires previous and current snapshots";
		final previousModules = moduleMap(previous);
		final currentModules = moduleMap(current);
		final moduleNames = unionModuleNames(previousModules, currentModules);
		final programConfigurationChanges = current.getProgramConfiguration().changedInputNames(previous.getProgramConfiguration());
		final sourceOriginChanges = new Array<String>();
		final conditionalCompilationChanges = new Array<String>();
		final generatedDeclarationChanges = new Array<String>();
		final macroFileDependencyChanges = new Array<String>();
		final publicChanges = new Array<String>();
		final implementationChanges = new Array<String>();
		final directSourceChanged = new haxe.ds.StringMap<Bool>();
		final sourceContentChanged = new haxe.ds.StringMap<Bool>();
		final sourceOriginChanged = new haxe.ds.StringMap<Bool>();
		final conditionalCompilationChanged = new haxe.ds.StringMap<Bool>();
		final generatedDeclarationsChanged = new haxe.ds.StringMap<Bool>();
		final macroFileDependenciesChanged = new haxe.ds.StringMap<Bool>();
		final publicChanged = new haxe.ds.StringMap<Bool>();
		final implementationChanged = new haxe.ds.StringMap<Bool>();

		for (modulePath in moduleNames) {
			final before = previousModules.get(modulePath);
			final after = currentModules.get(modulePath);
			if (before == null || after == null || before.sourceOriginRevision != after.sourceOriginRevision) {
				sourceOriginChanges.push(modulePath);
				sourceOriginChanged.set(modulePath, true);
			}
			if (before != null
				&& after != null
				&& before.conditionalCompilation.getCanonicalIdentity() != after.conditionalCompilation.getCanonicalIdentity()) {
				conditionalCompilationChanges.push(modulePath);
				conditionalCompilationChanged.set(modulePath, true);
			}
			if (before != null
				&& after != null
				&& before.generatedDeclarations.getCanonicalIdentity() != after.generatedDeclarations.getCanonicalIdentity()) {
				generatedDeclarationChanges.push(modulePath);
				generatedDeclarationsChanged.set(modulePath, true);
			}
			if (before != null
				&& after != null
				&& before.macroFileDependencies.getCanonicalIdentity() != after.macroFileDependencies.getCanonicalIdentity()) {
				macroFileDependencyChanges.push(modulePath);
				macroFileDependenciesChanged.set(modulePath, true);
			}
			if (before == null || after == null || before.publicInterfaceRevision != after.publicInterfaceRevision) {
				publicChanges.push(modulePath);
				publicChanged.set(modulePath, true);
			}
			if (before == null || after == null || before.implementationRevision != after.implementationRevision) {
				implementationChanges.push(modulePath);
				implementationChanged.set(modulePath, true);
			}
			if (before == null || after == null || before.sourceRevision != after.sourceRevision)
				sourceContentChanged.set(modulePath, true);
			if (before == null
				|| after == null
				|| before.sourceRevision != after.sourceRevision
				|| conditionalCompilationChanged.exists(modulePath)
				|| generatedDeclarationsChanged.exists(modulePath)
				|| macroFileDependenciesChanged.exists(modulePath))
				directSourceChanged.set(modulePath, true);
		}

		final reverseEdges = reverseEdgeMap(previous, current);
		final strengthByModule = new haxe.ds.StringMap<Int>();
		final reasonByModule = new haxe.ds.StringMap<Array<String>>();
		final queue = new Array<String>();
		for (modulePath in moduleNames) {
			if (!directSourceChanged.exists(modulePath))
				continue;
			if (sourceOriginChanged.exists(modulePath)) {
				final before = previousModules.get(modulePath);
				final after = currentModules.get(modulePath);
				final strength = publicChanged.exists(modulePath) ? PUBLIC_INTERFACE_CHANGE : (implementationChanged.exists(modulePath) ? IMPLEMENTATION_CHANGE : MODULE_INPUT_CHANGE);
				final beforeOrigin = before == null ? "<missing>" : before.sourceOriginDescription;
				final afterOrigin = after == null ? "<missing>" : after.sourceOriginDescription;
				mark(modulePath, strength, ["source-origin-changed:" + modulePath + ":" + beforeOrigin + "->" + afterOrigin], strengthByModule,
					reasonByModule, queue);
			} else if (conditionalCompilationChanged.exists(modulePath)) {
				final before = previousModules.get(modulePath);
				final after = currentModules.get(modulePath);
				final strength = publicChanged.exists(modulePath) ? PUBLIC_INTERFACE_CHANGE : (implementationChanged.exists(modulePath) ? IMPLEMENTATION_CHANGE : MODULE_INPUT_CHANGE);
				final changedNames = after == null ? [] : after.conditionalCompilation.changedDefineNames(before == null ? null : before.conditionalCompilation);
				final description = changedNames.length == 0 ? "<selection>" : changedNames.join(",");
				mark(modulePath, strength, ["conditional-compilation-changed:" + modulePath + ":" + description], strengthByModule, reasonByModule, queue);
			} else if (generatedDeclarationsChanged.exists(modulePath)) {
				final strength = publicChanged.exists(modulePath) ? PUBLIC_INTERFACE_CHANGE : (implementationChanged.exists(modulePath) ? IMPLEMENTATION_CHANGE : MODULE_INPUT_CHANGE);
				mark(modulePath, strength, ["generated-declarations-changed:" + modulePath], strengthByModule, reasonByModule, queue);
			} else if (sourceContentChanged.exists(modulePath)) {
				final strength = publicChanged.exists(modulePath) ? PUBLIC_INTERFACE_CHANGE : (implementationChanged.exists(modulePath) ? IMPLEMENTATION_CHANGE : MODULE_INPUT_CHANGE);
				final reason = publicChanged.exists(modulePath) ? "public-interface-changed:" : (implementationChanged.exists(modulePath) ? "implementation-changed:" : "source-changed:");
				mark(modulePath, strength, [reason + modulePath], strengthByModule, reasonByModule, queue);
			} else if (macroFileDependenciesChanged.exists(modulePath)) {
				final strength = publicChanged.exists(modulePath) ? PUBLIC_INTERFACE_CHANGE : (implementationChanged.exists(modulePath) ? IMPLEMENTATION_CHANGE : MODULE_INPUT_CHANGE);
				mark(modulePath, strength, ["macro-file-dependency-changed:" + modulePath], strengthByModule, reasonByModule, queue);
			} else if (publicChanged.exists(modulePath)) {
				mark(modulePath, PUBLIC_INTERFACE_CHANGE, ["public-interface-changed:" + modulePath], strengthByModule, reasonByModule, queue);
			} else if (implementationChanged.exists(modulePath)) {
				mark(modulePath, IMPLEMENTATION_CHANGE, ["implementation-changed:" + modulePath], strengthByModule, reasonByModule, queue);
			}
		}
		if (programConfigurationChanges.length > 0)
			for (module in current.getModules())
				mark(module.modulePath, MODULE_INPUT_CHANGE, ["program-configuration-changed:" + programConfigurationChanges.join(",")], strengthByModule,
					reasonByModule, queue);

		var cursor = 0;
		while (cursor < queue.length) {
			final providerModule = queue[cursor++];
			final providerStrength = strengthByModule.get(providerModule);
			final providerReason = reasonByModule.get(providerModule);
			final edges = reverseEdges.get(providerModule);
			if (providerStrength == null || providerReason == null || edges == null)
				continue;
			if (providerStrength == MODULE_INPUT_CHANGE)
				continue;
			for (edge in edges) {
				if (providerStrength == IMPLEMENTATION_CHANGE && !CompilerDependencyKindTools.consumesImplementation(edge.kind))
					continue;
				final consumerStrength = publicChanged.exists(edge.consumerModule) ? PUBLIC_INTERFACE_CHANGE : IMPLEMENTATION_CHANGE;
				final nextReason = providerReason.concat([CompilerDependencyKindTools.name(edge.kind)
					+ ":"
					+ edge.consumerModule
					+ "->"
					+ edge.providerModule
					+ ":"
					+ edge.factIdentity
					+ "@"
					+ CompilerDependencyPhaseTools.name(edge.phase)]);
				mark(edge.consumerModule, consumerStrength, nextReason, strengthByModule, reasonByModule, queue);
			}
		}

		final invalidations = new Array<CompilerDependencyInvalidation>();
		for (modulePath in strengthByModule.keys())
			invalidations.push(new CompilerDependencyInvalidation(modulePath, reasonByModule.get(modulePath)));
		return new CompilerDependencyComparison(programConfigurationChanges, sourceOriginChanges, conditionalCompilationChanges, generatedDeclarationChanges,
			macroFileDependencyChanges, publicChanges, implementationChanges, invalidations);
	}

	static function mark(modulePath:String, strength:Int, reason:Array<String>, strengthByModule:haxe.ds.StringMap<Int>,
			reasonByModule:haxe.ds.StringMap<Array<String>>, queue:Array<String>):Void {
		final previousStrength = strengthByModule.get(modulePath);
		if (previousStrength != null && previousStrength >= strength)
			return;
		strengthByModule.set(modulePath, strength);
		reasonByModule.set(modulePath, reason.copy());
		queue.push(modulePath);
	}

	static function moduleMap(snapshot:CompilerDependencySnapshot):haxe.ds.StringMap<CompilerTypedModuleRevision> {
		final out = new haxe.ds.StringMap<CompilerTypedModuleRevision>();
		for (module in snapshot.getModules())
			out.set(module.modulePath, module);
		return out;
	}

	static function unionModuleNames(previous:haxe.ds.StringMap<CompilerTypedModuleRevision>,
			current:haxe.ds.StringMap<CompilerTypedModuleRevision>):Array<String> {
		final names = new haxe.ds.StringMap<Bool>();
		for (name in previous.keys())
			names.set(name, true);
		for (name in current.keys())
			names.set(name, true);
		final out = new Array<String>();
		for (name in names.keys())
			out.push(name);
		out.sort(compareText);
		return out;
	}

	static function reverseEdgeMap(previous:CompilerDependencySnapshot, current:CompilerDependencySnapshot):haxe.ds.StringMap<Array<CompilerDependencyEdge>> {
		final byKey = new haxe.ds.StringMap<CompilerDependencyEdge>();
		for (edge in previous.getEdges())
			byKey.set(edge.canonicalKey(), edge);
		for (edge in current.getEdges())
			byKey.set(edge.canonicalKey(), edge);
		final reverse = new haxe.ds.StringMap<Array<CompilerDependencyEdge>>();
		for (edge in byKey) {
			final edges = reverse.get(edge.providerModule);
			if (edges == null) {
				final created = new Array<CompilerDependencyEdge>();
				created.push(edge);
				reverse.set(edge.providerModule, created);
			} else {
				edges.push(edge);
			}
		}
		for (edges in reverse)
			edges.sort(compareEdges);
		return reverse;
	}

	static function compareEdges(left:CompilerDependencyEdge, right:CompilerDependencyEdge):Int {
		final leftPriority = CompilerDependencyKindTools.consumesImplementation(left.kind) ? 0 : 1;
		final rightPriority = CompilerDependencyKindTools.consumesImplementation(right.kind) ? 0 : 1;
		if (leftPriority < rightPriority)
			return -1;
		if (leftPriority > rightPriority)
			return 1;
		return compareText(left.canonicalKey(), right.canonicalKey());
	}

	static function compareText(left:String, right:String):Int
		return left < right ? -1 : (left > right ? 1 : 0);
}
