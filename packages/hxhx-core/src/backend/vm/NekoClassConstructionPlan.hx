package backend.vm;

import haxe.ds.StringMap;

/** A method implementation and the exact class whose scope owns its body. */
typedef NekoConstructionMethod = {
	final owner:TypedBackendClassProjection;
	final body:TypedBackendFunctionProjection;
};

/**
	Selects inherited object members from the exact typed superclass graph.

	The allocator installs the most-derived method implementations before any
	constructor executes. Each class initializer then runs on that same receiver.
	The child-to-root order preserves override selection without copying closures
	from a separately allocated base object. Missing ancestors are errors.
**/
class NekoClassConstructionPlan {
	public final lineage:Array<TypedBackendClassProjection>;
	public final methods:Array<NekoConstructionMethod>;

	final instanceFields = new StringMap<Bool>();
	final instanceMethods = new StringMap<Bool>();

	public function new(graph:TypedBackendClassGraph, program:NekoTypedProgramProjection, identity:String) {
		final nodes = graph.requireLineage(identity);
		lineage = [for (node in nodes) program.requireClass(node.classIdentity)];
		for (node in nodes) {
			final facts = graph.findClassFacts(node.classIdentity);
			if (facts == null)
				throw "Neko construction lost class facts for " + node.classIdentity;
			for (field in facts.copyFields())
				if (!field.isStatic)
					instanceFields.set(field.name, true);
		}
		methods = [];
		for (owner in lineage) {
			for (body in owner.getFunctions()) {
				final declaration = body.getDeclaration();
				final name = HxFunctionDecl.getName(declaration);
				if (name == "new"
					|| HxFunctionDecl.getIsStatic(declaration)
					|| HxFunctionDecl.getMetadata(declaration).indexOf("macro") >= 0)
					continue;
				if (!instanceMethods.exists(name)) {
					instanceMethods.set(name, true);
					methods.push({owner: owner, body: body});
				}
			}
		}
	}

	/** Only the selected zero-argument String method can supply the VM conversion hook. */
	public function hasStringConversion():Bool {
		for (method in methods)
			if (HxFunctionDecl.getName(method.body.getDeclaration()) == "toString") {
				final result = method.body.getReturnType().getSemanticKey();
				return method.body.getParameters().length == 0 && (result == "primitive:String" || result == "nominal:String");
			}
		return false;
	}

	/** Bare inherited reads use the receiver only after local shadowing is resolved. */
	public function hasInstanceField(name:String):Bool
		return instanceFields.exists(name);

	public function hasInstanceMethod(name:String):Bool
		return instanceMethods.exists(name);

	/** An omitted constructor forwards the nearest inherited constructor parameters. */
	public function effectiveConstructor():Null<HxFunctionDecl> {
		for (owner in lineage)
			for (body in owner.getFunctions()) {
				final declaration = body.getDeclaration();
				if (HxFunctionDecl.getName(declaration) == "new" && !HxFunctionDecl.getIsStatic(declaration))
					return declaration;
			}
		return null;
	}
}
