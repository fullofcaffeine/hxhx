package backend.vm;

import haxe.ds.StringMap;

/** A method implementation and the exact class whose scope owns its body. */
typedef NekoConstructionMethod = {
	final owner:TypedBackendClassProjection;
	final body:TypedBackendFunctionProjection;
};

/**
	Selects construction representation and inherited members from exact typed owners.

	The allocator installs the most-derived method implementations before any
	constructor executes. Each class initializer then runs on that same receiver.
	The child-to-root order preserves override selection without copying closures
	from a separately allocated base object. Abstract factories instead return their
	backing value. Missing ancestors are errors.
**/
class NekoClassConstructionPlan {
	/** An abstract factory returns its backing value rather than a class instance. */
	public final returnsBackingValue:Bool;

	public final lineage:Array<TypedBackendClassProjection>;
	public final methods:Array<NekoConstructionMethod>;

	final instanceFields = new StringMap<Bool>();
	final instanceMethods = new StringMap<Bool>();

	public function new(graph:TypedBackendClassGraph, program:NekoTypedProgramProjection, identity:String) {
		returnsBackingValue = program.constructorReturnsBackingValue(identity);
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

	/** Inherited conversion hooks use dynamic receiver lookup; only an own method needs a new hook. */
	public function hasOwnStringConversion():Bool {
		for (method in methods)
			if (method.owner == lineage[0] && HxFunctionDecl.getName(method.body.getDeclaration()) == "toString") {
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
