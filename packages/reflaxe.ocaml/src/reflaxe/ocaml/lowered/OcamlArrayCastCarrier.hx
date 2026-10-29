package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.TypeTools;

/**
	Recognizes ordinary abstracts whose underlying storage is a standard Array.

	A cast from Dynamic must recover that array even when its destination keeps an
	abstract name. Follow declared type substitutions, never generated expressions.
	Core and native abstracts can own different layouts and remain excluded.
**/
function isArrayBackedAbstract(type:Type):Bool {
	var current = TypeTools.follow(type);
	var followedAbstract = false;
	for (_ in 0...32) {
		switch (current) {
			case TAbstract(reference, parameters):
				final declaration = reference.get();
				if (declaration.meta.has(":coreType") || declaration.meta.has(":native"))
					return false;
				followedAbstract = true;
				current = TypeTools.follow(TypeTools.applyTypeParameters(declaration.type, declaration.params, parameters));
			case TInst(reference, [_]):
				final declaration = reference.get();
				return followedAbstract && declaration.pack.length == 0 && declaration.module == "Array" && declaration.name == "Array";
			case _:
				return false;
		}
	}
	return false;
}
#end
