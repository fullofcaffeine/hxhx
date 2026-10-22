package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapCallContract;
import reflaxe.ocaml.lowered.OcamlMethodDispatchClassPlan;
import reflaxe.ocaml.lowered.OcamlMethodDispatchSignature;
import reflaxe.ocaml.lowered.OcamlMethodDispatchSignature.requireMethodSignature;
import reflaxe.ocaml.lowered.OcamlMethodDispatchRootPlan.fullName;

/** Checks retained interface implementations against every emitted method contract. */
class OcamlMethodDispatchProgram {
	var classes:Array<ClassType> = [];
	final structuralSources:Map<String, Bool> = [];
	final registrations:Map<String, {final revision:String; final keys:Array<String>;}> = [];
	final uses:Map<String, {final contract:ClassType; final signature:OcamlMethodDispatchSignature;}> = [];

	public function new() {}

	public function select(classes:Array<ClassType>):Void {
		this.classes = classes.copy();
		registrations.clear();
		uses.clear();
		structuralSources.clear();
		// This early inventory selects which concrete allocations need entries.
		// Final-root conversion checks and validate() still own acceptance.
		for (owner in classes) {
			final fields = owner.fields.get().concat(owner.statics.get());
			if (owner.constructor != null)
				fields.push(owner.constructor.get());
			for (field in fields) {
				final expression = field.expr();
				if (expression != null)
					OcamlMethodViewConversionPlan.visit(expression, field.type, null,
						(_, conversion) -> structuralSources.set(fullName(conversion.source), true));
			}
			if (owner.init != null)
				OcamlMethodViewConversionPlan.visit(owner.init, null, null, (_, conversion) -> structuralSources.set(fullName(conversion.source), true));
		}
	}

	/** Concrete structural sources and their subclasses need the same allocation-time entries. */
	public function requiresRegistration(owner:ClassType):Bool {
		var current:Null<ClassType> = owner;
		while (current != null) {
			if (structuralSources.exists(fullName(current)))
				return true;
			for (edge in current.interfaces)
				if (!OcamlStandardIMapCallContract.isIMapClass(edge.t.get()) && !edge.t.get().isExtern)
					return true;
			current = current.superClass == null ? null : current.superClass.t.get();
		}
		return false;
	}

	/** Both allocation routes must publish the same complete entries for a class. */
	public function recordClass(owner:ClassType, plan:OcamlMethodDispatchClassPlan):Void {
		final name = fullName(owner);
		if (plan.marker.runtimeClassName != name)
			throw "reflaxe.ocaml [ocaml-method-dispatch:wrong-class]: registration owner differs from its class marker";
		final previous = registrations.get(name);
		if (previous != null && previous.revision != plan.registryRevision)
			throw "reflaxe.ocaml [ocaml-method-dispatch:conflicting-allocations]: class allocation routes disagree";
		registrations.set(name, {revision: plan.registryRevision, keys: plan.entries.map(entry -> entry.signature.key)});
	}

	public function recordUse(contract:ClassType, signature:OcamlMethodDispatchSignature):Void {
		requireMethodSignature(signature);
		uses.set(fullName(contract) + ":" + signature.key, {contract: contract, signature: signature});
	}

	/** A known implementation cannot fall through to an unsafe or missing native entry. */
	public function validate():Void {
		for (use in uses)
			for (owner in classes) {
				if (owner.isInterface || !implementsContract(owner, fullName(use.contract), []))
					continue;
				final registered = registrations.get(fullName(owner));
				if (registered == null || !registered.keys.contains(use.signature.key))
					throw 'reflaxe.ocaml [ocaml-method-dispatch:missing-implementation]: ${fullName(owner)} lacks checked ${fullName(use.contract)}.${use.signature.methodName}';
			}
	}

	static function implementsContract(owner:ClassType, target:String, visited:Map<String, Bool>):Bool {
		final name = fullName(owner);
		if (visited.exists(name))
			return false;
		visited.set(name, true);
		if (name == target)
			return true;
		for (edge in owner.interfaces)
			if (implementsContract(edge.t.get(), target, visited))
				return true;
		return owner.superClass != null && implementsContract(owner.superClass.t.get(), target, visited);
	}
}
#end
