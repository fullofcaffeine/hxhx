package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;

/** The declaration that supplies an instance method after Haxe override resolution. */
typedef OcamlInstanceMethodDeclaration = {
	final owner:ClassType;
	final field:ClassField;
}

/**
	One class's inherited method order and effective implementations.

	Record layout uses the first declaration's position. Calls use the most-derived
	implementation at that position. Interface dispatch must consume these same
	facts; it must not infer an implementation from an interface record offset.
	These are declaration facts, not permission to erase a receiver or call a method.
**/
typedef OcamlInstanceMethodCatalog = {
	final chain:Array<ClassType>;
	final order:Array<String>;
	final declarations:Map<String, OcamlInstanceMethodDeclaration>;
}

/** Returns methods declared at one inheritance level, in the typed source order. */
function declaredInstanceMethods(owner:ClassType):Array<ClassField> {
	final result:Array<ClassField> = [];
	for (field in owner.fields.get()) {
		if (field == null || field.name == "new")
			continue;
		switch (field.kind) {
			case FMethod(_):
				result.push(field);
			case _:
		}
	}
	return result;
}

/**
	Collects the existing concrete dispatch order once for all dispatch consumers.

	Haxe has already checked inheritance and overrides. This function preserves
	declarations without substituting generic parameters or choosing native types.
	Each consumer must separately prove its supported signatures and receiver types.
**/
function collectInstanceMethods(owner:ClassType):OcamlInstanceMethodCatalog {
	final chain:Array<ClassType> = [];
	var current:Null<ClassType> = owner;
	final visited:Map<String, Bool> = [];
	while (current != null) {
		final identity = current.module + ":" + current.pack.concat([current.name]).join(".");
		if (visited.exists(identity))
			throw 'reflaxe.ocaml [ocaml-method-catalog:inheritance-cycle]: $identity';
		visited.set(identity, true);
		chain.push(current);
		current = current.superClass == null ? null : current.superClass.t.get();
	}
	chain.reverse();
	final order:Array<String> = [];
	final declarations:Map<String, OcamlInstanceMethodDeclaration> = [];
	for (level in chain)
		for (field in declaredInstanceMethods(level)) {
			if (!declarations.exists(field.name))
				order.push(field.name);
			declarations.set(field.name, {owner: level, field: field});
		}
	return {chain: chain, order: order, declarations: declarations};
}
#end
