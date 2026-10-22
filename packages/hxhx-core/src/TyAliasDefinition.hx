/**
	A finite definition shared by recursive alias applications.

	Resolution allocates definitions before it binds their bodies. After every
	reachable body exists, seal() freezes the graph for semantic consumers. This
	checks graph construction, not whether an alias-only cycle is legal Haxe.
	The resolver must establish that separate rule before publishing a type use.
	Arguments belong to applications; expanding one application never rewrites
	the definition or precomputes later recursive applications.
 */
class TyAliasDefinition {
	final declaration:TyTypeDeclaration;
	final defaultIndex:Int;
	var body:Null<TyType>;
	var sealed:Bool = false;

	public function new(declaration:TyTypeDeclaration, ?defaultIndex:Int = -1) {
		switch (declaration.getKind()) {
			case Alias(source):
				if (defaultIndex < -1
					|| defaultIndex >= source.getParameters().length
					|| (defaultIndex >= 0 && source.getParameters()[defaultIndex].defaultType == null))
					throw "alias default requires an authored default parameter";
			case Nominal(_):
				throw "alias definition requires an alias declaration";
		}
		this.declaration = declaration;
		this.defaultIndex = defaultIndex;
	}

	public function getDeclaration():TyTypeDeclaration
		return declaration;

	/** Defaults have their own definition-site scope, outside the alias binders. */
	public function getParameterIds():Array<TyTypeParameterId>
		return defaultIndex < 0 ? declaration.getParameterIds() : [];

	/** Identify the body or the exact default slot without inventing a nominal type. */
	public function getCanonicalName():String
		return declaration.getCanonicalName() + (defaultIndex < 0 ? "" : "/default:" + defaultIndex);

	public function getSourceSyntax():HxTypeSyntax {
		return switch (declaration.getKind()) {
			case Alias(source): defaultIndex < 0 ? source.getTarget() : source.getParameters()[defaultIndex].defaultType;
			case Nominal(_): throw "alias definition lost its source declaration";
		};
	}

	/** The source resolver alone can read a bound body before graph publication. */
	@:allow(TyTypeUseResolution)
	function getBoundBody():Null<TyType>
		return body;

	/** Bind once while the resolver still owns the unpublished graph. */
	public function bind(value:TyType):Void {
		if (body != null || sealed || value == null)
			throw "alias definition must receive exactly one body: " + declaration.getCanonicalName();
		final parameters = getParameterIds();
		for (free in TyTypeSubstitution.freeParameterIdentities(value)) {
			var owned = false;
			for (parameter in parameters)
				if (free.equals(parameter))
					owned = true;
			if (!owned)
				throw "alias body contains a foreign type parameter: " + free.getCanonicalKey();
		}
		body = value;
	}

	/**
		Seal the complete reachable graph atomically. A missing body leaves all
		new definitions unpublished, including definitions reached through arguments.
	 */
	public static function seal(roots:Array<TyAliasDefinition>):Void {
		final pending = roots.copy();
		final visited = new Array<TyAliasDefinition>();
		function visitType(type:TyType):Void {
			final alias = type.getAliasDefinition();
			if (alias != null)
				pending.push(alias);
			if (type.isNullable())
				visitType(type.unwrapNull());
			if (type.isFunction())
				visitType(type.getFunctionReturn());
			for (child in type.getTypeArguments().concat(type.getFunctionArguments()).concat(type.getAnonymousFieldTypes()))
				visitType(child);
		}
		while (pending.length > 0) {
			final definition = pending.pop();
			if (visited.indexOf(definition) >= 0)
				continue;
			if (definition.body == null)
				throw "alias definition has no body: " + definition.declaration.getCanonicalName();
			visited.push(definition);
			visitType(definition.body);
		}
		for (definition in visited)
			definition.sealed = true;
	}

	/** Only sealed templates can participate in keys, expansion, or type scans. */
	public function getBody():TyType {
		if (!sealed || body == null)
			throw "alias definition is not sealed: " + declaration.getCanonicalName();
		return body;
	}

	/** Reveal one body with exact arguments, leaving recursive references finite. */
	public function instantiate(arguments:Array<TyType>):TyType {
		return TyTypeSubstitution.apply(getBody(), TyTypeSubstitution.bind(getParameterIds(), arguments, getCanonicalName()));
	}
}
