/**
	Finish a program's method input evidence before exposing its final typed modules.
	Later callers can constrain declarations in modules already traversed. Rebuild
	those snapshots from their original sources, without mutating retained copies.
	New dependencies enter the same worklist. Repeated sweeps stop once no input
	evidence changes; the input owner only fills previously unknown slots.
 */
function finish(input:{
	modules:Array<TypedModule>,
	index:TyperIndex,
	?loader:ModuleLoader,
	?beforeModule:() -> Void,
	?onDiscovered:ResolvedModule->Void
}):Array<TypedModule> {
	final result = input.modules.copy();
	final known = new haxe.ds.StringMap<Bool>();
	for (module in result)
		known.set(ResolvedModule.getModulePath(input.index.getTypedInputRevision(module).source), true);
	var changed:Bool;
	do {
		changed = false;
		for (position in 0...result.length) {
			final prior = input.index.getTypedInputRevision(result[position]);
			if (prior.revision == input.index.getMethodInputs().getRevision())
				continue;
			if (input.beforeModule != null)
				input.beforeModule();
			result[position] = TyperStage.typeResolvedModule(prior.source, input.index, input.loader, prior.deferProgramLowering);
			changed = true;
		}
		if (input.loader != null)
			for (source in input.loader.drainNewModules()) {
				final path = ResolvedModule.getModulePath(source);
				if (known.exists(path))
					continue;
				known.set(path, true);
				if (input.beforeModule != null)
					input.beforeModule();
				if (input.onDiscovered != null)
					input.onDiscovered(source);
				result.push(TyperStage.typeResolvedModule(source, input.index, input.loader, true));
				changed = true;
			}
	} while (changed);
	return result;
}
