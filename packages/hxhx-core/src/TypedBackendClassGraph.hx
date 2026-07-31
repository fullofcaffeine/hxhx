import TypedBackendClassSemanticFacts.TypedBackendClassFieldFact;
import TypedBackendClassSemanticFacts.TypedBackendClassMethodFact;

typedef TypedBackendClassGraphNode = {
	final classIdentity:String;
	final moduleIdentity:String;
	final classFactsIdentity:String;
	final superClassIdentity:Null<String>;
	final superTypeIdentity:Null<String>;
	final superTypeDisplay:Null<String>;
};

typedef TypedBackendClassLineage = {
	final nodes:Array<TypedBackendClassGraphNode>;
	final complete:Bool;
	final missingParentIdentity:Null<String>;
};

typedef TypedBackendClassTypeBinding = {
	final parameterIdentity:String;
	final parameterName:String;
	final semanticType:TyType;
	final typeIdentity:String;
	final typeDisplay:String;
};

typedef TypedBackendSpecializedClassNode = {
	final classIdentity:String;
	final moduleIdentity:String;
	final classFactsIdentity:String;
	final bindings:Array<TypedBackendClassTypeBinding>;
	final fields:Array<TypedBackendClassFieldFact>;
	final methods:Array<TypedBackendClassMethodFact>;
};

/**
	Immutable exact inheritance graph for one sealed typed backend program.

	Nodes are keyed only by canonical Haxe type identity. An edge retains both
	the raw parent node and the applied superclass type so later lowering can
	distinguish `Base` from `Base<String>` without parsing display text.

	A missing parent node is not treated as a root. `traceLineage` reports the
	incomplete edge, while `requireLineage` fails before a target can silently
	drop inherited members. An unresolved superclass may coexist in the catalog
	until a caller asks to consume that class's lineage; unrelated executable
	units are not rejected merely because their program also contains an
	unresolved external class.
**/
class TypedBackendClassGraph {
	final programRevision:String;
	final factsByClass:haxe.ds.StringMap<TypedBackendClassSemanticFacts>;
	final nodesByClass:haxe.ds.StringMap<TypedBackendClassGraphNode>;
	final nodes:Array<TypedBackendClassGraphNode>;
	final canonicalIdentity:String;

	public function new(programRevision:String, facts:Array<TypedBackendClassSemanticFacts>) {
		this.programRevision = normalize(programRevision);
		if (this.programRevision.length == 0)
			throw "typed backend class graph requires an exact typed-program revision";

		factsByClass = new haxe.ds.StringMap<TypedBackendClassSemanticFacts>();
		nodesByClass = new haxe.ds.StringMap<TypedBackendClassGraphNode>();
		if (facts != null)
			for (classFacts in facts)
				addFacts(classFacts);

		final classIdentities = [for (identity in nodesByClass.keys()) identity];
		classIdentities.sort((left, right) -> Reflect.compare(left, right));
		nodes = [for (identity in classIdentities) copyNode(nodesByClass.get(identity))];
		for (node in nodes)
			validateLineage(node.classIdentity);

		final identityFacts = new Array<Null<String>>();
		identityFacts.push(getSchemaRevision());
		identityFacts.push(this.programRevision);
		identityFacts.push(Std.string(nodes.length));
		for (node in nodes) {
			identityFacts.push(node.classIdentity);
			identityFacts.push(node.moduleIdentity);
			identityFacts.push(node.classFactsIdentity);
			identityFacts.push(node.superClassIdentity);
			identityFacts.push(node.superTypeIdentity);
			identityFacts.push(node.superTypeDisplay);
		}
		canonicalIdentity = CompilerCacheIdentity.encode(identityFacts);
	}

	/** Return the exact target-neutral program revision that owns this graph. **/
	public function getProgramRevision():String
		return programRevision;

	/** Return the independently versioned graph representation schema. **/
	public function getSchemaRevision():String
		return "typed-backend-class-graph-v3";

	/** Return the deterministic in-memory identity of the complete graph. **/
	public function getCanonicalIdentity():String
		return canonicalIdentity;

	public function copyNodes():Array<TypedBackendClassGraphNode>
		return [for (node in nodes) copyNode(node)];

	public function findNode(classIdentity:String):Null<TypedBackendClassGraphNode> {
		final node = nodesByClass.get(normalize(classIdentity));
		return node == null ? null : copyNode(node);
	}

	/** Return the immutable declared-member record owned by one exact node. **/
	public function findClassFacts(classIdentity:String):Null<TypedBackendClassSemanticFacts>
		return factsByClass.get(normalize(classIdentity));

	/**
		Trace one child-to-root chain without hiding an absent projected parent.

		An unknown starting class is a caller error. An absent parent reached from
		a known node is a valid incomplete observation and is named explicitly.
	**/
	public function traceLineage(classIdentity:String):TypedBackendClassLineage {
		final start = normalize(classIdentity);
		if (start.length == 0 || !nodesByClass.exists(start))
			throw "typed backend class graph does not contain class " + start;
		final lineage = new Array<TypedBackendClassGraphNode>();
		var currentIdentity:Null<String> = start;
		while (currentIdentity != null) {
			final current = nodesByClass.get(currentIdentity);
			if (current == null)
				return {nodes: lineage, complete: false, missingParentIdentity: currentIdentity};
			lineage.push(copyNode(current));
			if (current.superTypeIdentity == null)
				return {nodes: lineage, complete: true, missingParentIdentity: null};
			if (current.superClassIdentity == null)
				throw "typed backend class graph cannot identify nominal superclass node for "
					+ current.classIdentity
					+ " ("
					+ current.superTypeIdentity
					+ ")";
			currentIdentity = current.superClassIdentity;
		}
		return {nodes: lineage, complete: true, missingParentIdentity: null};
	}

	/**
		Return a complete child-to-root chain or fail at the first absent parent.

		Production lowering should use this strict form whenever inherited members
		affect generated behavior.
	**/
	public function requireLineage(classIdentity:String):Array<TypedBackendClassGraphNode> {
		final lineage = traceLineage(classIdentity);
		if (!lineage.complete)
			throw "typed backend class graph is missing superclass "
				+ lineage.missingParentIdentity
				+ " while tracing "
				+ normalize(classIdentity);
		return [for (node in lineage.nodes) copyNode(node)];
	}

	/**
		Return declared member facts as seen from one exact child class.

		Every superclass edge applies its structural type arguments to the parent
		class's exact binder identities. Method-level binders remain untouched,
		even when they use the same readable name as a class-level binder.
	**/
	public function requireSpecializedLineage(classIdentity:String):Array<TypedBackendSpecializedClassNode> {
		final startIdentity = normalize(classIdentity);
		final startFacts = factsByClass.get(startIdentity);
		if (startFacts == null)
			throw "typed backend class graph does not contain class facts for " + startIdentity;
		return specializeLineage(startIdentity, TyTypeSubstitution.identity(startFacts.getTypeParameterIds(), startIdentity));
	}

	/**
		Return declared member facts as seen through one exact applied class type.

		For `Box<Int->Int>`, a field declared as `value:T` is returned as the
		actual function type. This keeps target member decisions structural and
		prevents them from guessing generic substitutions from display text.
	**/
	public function requireSpecializedLineageForType(type:TyType):Array<TypedBackendSpecializedClassNode> {
		if (type == null)
			throw "typed backend class graph cannot specialize a null semantic type";
		final nominal = type.getNominalIdentity();
		if (nominal == null)
			throw "typed backend class graph cannot specialize non-nominal type " + type.getSemanticKey();
		final startIdentity = nominal.getCanonicalName();
		final startFacts = factsByClass.get(startIdentity);
		if (startFacts == null)
			throw "typed backend class graph does not contain class facts for " + startIdentity;
		return specializeLineage(startIdentity, TyTypeSubstitution.bind(startFacts.getTypeParameterIds(), type.getTypeArguments(), type.getSemanticKey()));
	}

	function specializeLineage(startIdentity:String, initialBindings:haxe.ds.StringMap<TyType>):Array<TypedBackendSpecializedClassNode> {
		final lineage = requireLineage(startIdentity);
		var bindings = initialBindings;
		final specialized = new Array<TypedBackendSpecializedClassNode>();

		for (index in 0...lineage.length) {
			final node = lineage[index];
			final classFacts = factsByClass.get(node.classIdentity);
			if (classFacts == null)
				throw "typed backend class graph does not contain class facts for " + node.classIdentity;
			specialized.push(specializeNode(node, classFacts, bindings));
			if (node.superClassIdentity == null)
				continue;

			final structuralSuperType = classFacts.getSuperType();
			if (structuralSuperType == null)
				throw "typed backend class graph is missing structural superclass type for " + node.classIdentity;
			final appliedSuperType = TyTypeSubstitution.apply(structuralSuperType, bindings);
			final appliedSuperIdentity = appliedSuperType.getNominalIdentity();
			if (appliedSuperIdentity == null || appliedSuperIdentity.getCanonicalName() != node.superClassIdentity)
				throw "typed backend class graph contains conflicting structural superclass for " + node.classIdentity;
			final parentFacts = factsByClass.get(node.superClassIdentity);
			if (parentFacts == null)
				throw "typed backend class graph is missing superclass " + node.superClassIdentity + " while specializing " + startIdentity;
			bindings = TyTypeSubstitution.bind(parentFacts.getTypeParameterIds(), appliedSuperType.getTypeArguments(),
				node.classIdentity + " -> " + node.superClassIdentity);
		}
		return [for (node in specialized) copySpecializedNode(node)];
	}

	function addFacts(classFacts:TypedBackendClassSemanticFacts):Void {
		if (classFacts == null)
			throw "typed backend class graph contains a null class fact";
		final classIdentity = normalize(classFacts.getClassIdentity());
		final moduleIdentity = normalize(classFacts.getModuleIdentity());
		final classFactsIdentity = normalize(classFacts.getCanonicalIdentity());
		if (classIdentity.length == 0 || moduleIdentity.length == 0 || classFactsIdentity.length == 0)
			throw "typed backend class graph contains an incomplete class fact";
		final node:TypedBackendClassGraphNode = {
			classIdentity: classIdentity,
			moduleIdentity: moduleIdentity,
			classFactsIdentity: classFactsIdentity,
			superClassIdentity: normalizeNullable(classFacts.getSuperClassIdentity()),
			superTypeIdentity: normalizeNullable(classFacts.getSuperTypeIdentity()),
			superTypeDisplay: normalizeNullable(classFacts.getSuperTypeDisplay())
		};
		if ((node.superTypeIdentity == null) != (node.superTypeDisplay == null))
			throw "typed backend class graph contains an incomplete superclass type for " + classIdentity;
		final structuralSuperType = classFacts.getSuperType();
		if ((structuralSuperType == null) != (node.superTypeIdentity == null)
			|| (structuralSuperType != null
				&& (structuralSuperType.getSemanticKey() != node.superTypeIdentity
					|| structuralSuperType.getCanonicalDisplay() != node.superTypeDisplay)))
			throw "typed backend class graph contains conflicting structural superclass type for " + classIdentity;
		if (node.superClassIdentity == classIdentity)
			throw "typed backend class graph contains self-inheritance for " + classIdentity;

		final previous = nodesByClass.get(classIdentity);
		if (previous == null) {
			nodesByClass.set(classIdentity, copyNode(node));
			factsByClass.set(classIdentity, classFacts);
		} else if (!sameNode(previous, node)) {
			throw "typed backend class graph contains conflicting class " + classIdentity;
		}
	}

	function validateLineage(start:String):Void {
		final visited = new haxe.ds.StringMap<Bool>();
		var currentIdentity:Null<String> = start;
		while (currentIdentity != null) {
			if (visited.exists(currentIdentity))
				throw "typed backend class graph contains inheritance cycle at " + currentIdentity + " while tracing " + start;
			visited.set(currentIdentity, true);
			final current = nodesByClass.get(currentIdentity);
			if (current == null)
				return;
			if (current.superTypeIdentity != null && current.superClassIdentity == null)
				return;
			currentIdentity = current.superClassIdentity;
		}
	}

	static function sameNode(left:TypedBackendClassGraphNode, right:TypedBackendClassGraphNode):Bool
		return left.classIdentity == right.classIdentity
			&& left.moduleIdentity == right.moduleIdentity
			&& left.classFactsIdentity == right.classFactsIdentity
			&& left.superClassIdentity == right.superClassIdentity
			&& left.superTypeIdentity == right.superTypeIdentity
			&& left.superTypeDisplay == right.superTypeDisplay;

	static function copyNode(node:TypedBackendClassGraphNode):TypedBackendClassGraphNode
		return {
			classIdentity: node.classIdentity,
			moduleIdentity: node.moduleIdentity,
			classFactsIdentity: node.classFactsIdentity,
			superClassIdentity: node.superClassIdentity,
			superTypeIdentity: node.superTypeIdentity,
			superTypeDisplay: node.superTypeDisplay
		};

	static function specializeNode(node:TypedBackendClassGraphNode, classFacts:TypedBackendClassSemanticFacts,
			bindings:haxe.ds.StringMap<TyType>):TypedBackendSpecializedClassNode {
		final bindingFacts = new Array<TypedBackendClassTypeBinding>();
		for (parameter in classFacts.getTypeParameterIds()) {
			final bound = bindings.get(parameter.getCanonicalKey());
			if (bound == null)
				throw "typed backend class graph is missing binding for " + parameter.getName() + " in " + node.classIdentity;
			bindingFacts.push({
				parameterIdentity: parameter.getCanonicalKey(),
				parameterName: parameter.getName(),
				semanticType: bound,
				typeIdentity: bound.getSemanticKey(),
				typeDisplay: bound.getCanonicalDisplay()
			});
		}
		return {
			classIdentity: node.classIdentity,
			moduleIdentity: node.moduleIdentity,
			classFactsIdentity: node.classFactsIdentity,
			bindings: bindingFacts,
			fields: [for (field in classFacts.copyFields()) specializeField(field, bindings)],
			methods: [for (method in classFacts.copyMethods()) specializeMethod(method, bindings)]
		};
	}

	static function specializeField(field:TypedBackendClassFieldFact, bindings:haxe.ds.StringMap<TyType>):TypedBackendClassFieldFact {
		final semanticType = TyTypeSubstitution.apply(field.semanticType, bindings);
		return {
			canonicalIdentity: field.canonicalIdentity,
			name: field.name,
			semanticType: semanticType,
			typeIdentity: semanticType.getSemanticKey(),
			typeDisplay: semanticType.getCanonicalDisplay(),
			isStatic: field.isStatic,
			isPublic: field.isPublic,
			isFinal: field.isFinal,
			isInline: field.isInline,
			hasInitializer: field.hasInitializer,
			propertyGet: field.propertyGet,
			propertySet: field.propertySet,
			noImportGlobal: field.noImportGlobal
		};
	}

	static function specializeMethod(method:TypedBackendClassMethodFact, bindings:haxe.ds.StringMap<TyType>):TypedBackendClassMethodFact {
		final returnType = TyTypeSubstitution.apply(method.returnSemanticType, bindings);
		return {
			canonicalIdentity: method.canonicalIdentity,
			name: method.name,
			isStatic: method.isStatic,
			typeParameters: method.typeParameters.copy(),
			arguments: [
				for (argument in method.arguments) {
					final semanticType = TyTypeSubstitution.apply(argument.semanticType, bindings);
					{
						name: argument.name,
						semanticType: semanticType,
						typeIdentity: semanticType.getSemanticKey(),
						typeDisplay: semanticType.getCanonicalDisplay(),
						isOptional: argument.isOptional,
						isRest: argument.isRest
					};
				}
			],
			returnSemanticType: returnType,
			returnTypeIdentity: returnType.getSemanticKey(),
			returnTypeDisplay: returnType.getCanonicalDisplay(),
			isPublic: method.isPublic,
			isInline: method.isInline,
			isDynamic: method.isDynamic,
			hasBody: method.hasBody,
			isEnumConstructor: method.isEnumConstructor,
			noImportGlobal: method.noImportGlobal
		};
	}

	static function copySpecializedNode(node:TypedBackendSpecializedClassNode):TypedBackendSpecializedClassNode
		return {
			classIdentity: node.classIdentity,
			moduleIdentity: node.moduleIdentity,
			classFactsIdentity: node.classFactsIdentity,
			bindings: [
				for (binding in node.bindings)
					{
						parameterIdentity: binding.parameterIdentity,
						parameterName: binding.parameterName,
						semanticType: binding.semanticType,
						typeIdentity: binding.typeIdentity,
						typeDisplay: binding.typeDisplay
					}
			],
			fields: [for (field in node.fields) copySpecializedField(field)],
			methods: [for (method in node.methods) copySpecializedMethod(method)]
		};

	static function copySpecializedField(field:TypedBackendClassFieldFact):TypedBackendClassFieldFact
		return {
			canonicalIdentity: field.canonicalIdentity,
			name: field.name,
			semanticType: field.semanticType,
			typeIdentity: field.typeIdentity,
			typeDisplay: field.typeDisplay,
			isStatic: field.isStatic,
			isPublic: field.isPublic,
			isFinal: field.isFinal,
			isInline: field.isInline,
			hasInitializer: field.hasInitializer,
			propertyGet: field.propertyGet,
			propertySet: field.propertySet,
			noImportGlobal: field.noImportGlobal
		};

	static function copySpecializedMethod(method:TypedBackendClassMethodFact):TypedBackendClassMethodFact
		return {
			canonicalIdentity: method.canonicalIdentity,
			name: method.name,
			isStatic: method.isStatic,
			typeParameters: method.typeParameters.copy(),
			arguments: [
				for (argument in method.arguments)
					{
						name: argument.name,
						semanticType: argument.semanticType,
						typeIdentity: argument.typeIdentity,
						typeDisplay: argument.typeDisplay,
						isOptional: argument.isOptional,
						isRest: argument.isRest
					}
			],
			returnSemanticType: method.returnSemanticType,
			returnTypeIdentity: method.returnTypeIdentity,
			returnTypeDisplay: method.returnTypeDisplay,
			isPublic: method.isPublic,
			isInline: method.isInline,
			isDynamic: method.isDynamic,
			hasBody: method.hasBody,
			isEnumConstructor: method.isEnumConstructor,
			noImportGlobal: method.noImportGlobal
		};

	static function normalize(value:String):String
		return value == null ? "" : StringTools.trim(value);

	static function normalizeNullable(value:Null<String>):Null<String> {
		final normalized = normalize(value);
		return normalized.length == 0 ? null : normalized;
	}
}
