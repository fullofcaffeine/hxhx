/**
	Remove unused declarations from an immutable copy before executable lowering.
	The caller supplies exact reference closure under full/std policy. With DCE
	disabled, all declarations remain emitted even when feature discovery ignores
	their bodies. A decision belongs to one exact program, never a lookalike revision.
**/
class TypedEmissionRetention {
	final program:MacroExpandedProgram;
	final keepAll:Bool;
	final classes:haxe.ds.ObjectMap<TypedClass, Bool>;
	final functions:haxe.ds.ObjectMap<TypedFunction, Bool>;
	final fields:haxe.ds.ObjectMap<TyFieldInfo, Bool>;

	public function new(input:{reachable:TypedFeatureRoots.TypedFeatureRootSet, mode:String}) {
		program = input.reachable.program;
		program.assertTypedBodyRevisionsCurrent();
		keepAll = switch (input.mode) {
			case "no": true;
			case "full" | "std": false;
			case _: throw "unsupported emission retention mode: " + input.mode;
		};
		classes = new haxe.ds.ObjectMap();
		functions = new haxe.ds.ObjectMap();
		fields = new haxe.ds.ObjectMap();
		final owned = new haxe.ds.ObjectMap<TypedClass, Bool>();
		for (module in program.getTypedModules())
			for (owner in module.getTypedClasses())
				owned.set(owner, true);
		final functionOwners = new haxe.ds.ObjectMap<TypedFunction, Bool>();
		final fieldOwners = new haxe.ds.ObjectMap<TyFieldInfo, Bool>();
		for (owner in input.reachable.classes) {
			if (!owned.exists(owner) || owner.getSemanticInfo() == null || classes.exists(owner))
				throw "emission retention requires distinct owned classes";
			classes.set(owner, true);
			for (fn in owner.getFunctions())
				functionOwners.set(fn, true);
			for (source in owner.getFields()) {
				final field = owner.getSemanticInfo().fieldInfo(HxFieldDecl.getName(source));
				if (field == null)
					throw "emission retention requires exact field declarations";
				fieldOwners.set(field, true);
			}
		}
		for (fn in input.reachable.functions) {
			if (!functionOwners.exists(fn) || functions.exists(fn))
				throw "emission retention requires distinct functions of retained classes";
			functions.set(fn, true);
		}
		for (field in input.reachable.fields) {
			if (!fieldOwners.exists(field) || fields.exists(field))
				throw "emission retention requires distinct fields of retained classes";
			fields.set(field, true);
		}
	}

	/** The original program remains suitable for typing and later independent requests. */
	public function apply(ownerProgram:MacroExpandedProgram):MacroExpandedProgram {
		if (ownerProgram != program)
			throw "emission retention belongs to another typed program";
		program.assertTypedBodyRevisionsCurrent();
		if (keepAll)
			return program;
		var changed = false;
		final modules = new Array<TypedModule>();
		for (module in program.getTypedModules()) {
			var moduleChanged = false;
			final retainedClasses = new Array<TypedClass>();
			for (owner in module.getTypedClasses()) {
				if (!classes.exists(owner)) {
					moduleChanged = true;
					continue;
				}
				final retainedFunctions = [for (fn in owner.getFunctions()) if (functions.exists(fn)) fn];
				final retainedFields = [
					for (source in owner.getFields())
						if (fields.exists(owner.getSemanticInfo().fieldInfo(HxFieldDecl.getName(source)))) source
				];
				final retainedInitializers = [
					for (initializer in owner.getFieldInitializers())
						if (fields.exists(initializer.getField())) initializer
				];
				final classChanged = retainedFunctions.length != owner.getFunctions().length
					|| retainedFields.length != owner.getFields().length;
				if (classChanged)
					moduleChanged = true;
				retainedClasses.push(classChanged ? owner.withMembers({
					functions: retainedFunctions,
					fields: retainedFields,
					initializers: retainedInitializers
				}) : owner);
			}
			if (moduleChanged)
				changed = true;
			modules.push(moduleChanged ? module.withTypedClasses(retainedClasses) : module);
		}
		return changed ? new MacroExpandedProgram(modules, program.macroMode, program.getGeneratedOcamlModules()) : program;
	}
}
