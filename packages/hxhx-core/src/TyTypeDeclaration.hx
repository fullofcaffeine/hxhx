/** A source declaration can introduce a nominal type or a transparent alias. */
enum TyTypeDeclarationKind {
	Nominal(identity:TyNominalTypeId);
	Alias(source:HxTypedefDecl);
}

/** Lookup context belongs to the source use, independently of any selected declaration. */
typedef TyTypeResolutionContext = {
	final packagePath:String;
	final modulePath:String;
	final directives:Array<HxModuleDirective>;
	final filePath:String;
	final position:HxPos;
	final parameters:Array<TyTypeParameterId>;
};

/**
	How many type arguments an explicit application of a class, interface, enum or
	abstract may supply. `required` excludes trailing parameters with a default, so
	`class Def<A, B = String>` accepts `Def<Int>` and `Def<Int, Bool>`.
	`unbounded` removes the upper limit `total` would otherwise set, for a
	`@:genericBuild` class with a parameter named `Rest`: `class T<B, Rest>` accepts
	`T<Int>` and `T<Int, String, Bool>`, because its build macro receives the arguments.
**/
typedef TyNominalArity = {
	final total:Int;
	final required:Int;
	final unbounded:Bool;
};

/** Named header facts shared by declaration lookup and type instantiation. */
typedef TyTypeDeclarationInput = {
	final canonicalName:String;
	final visibility:HxVisibility;
	final kind:TyTypeDeclarationKind;
	final context:TyTypeResolutionContext;
	final ?nominalArity:TyNominalArity;
	final ?usesBuildMacro:Bool;
};

/**
	A named source declaration, without claiming that its target is a class.

	Headers become visible before signatures are resolved. An alias keeps its
	defining module context here so an importing module cannot change the meaning
	of the alias target. This record does not promise a completed signature.
 */
class TyTypeDeclaration {
	final canonicalName:String;
	final visibility:HxVisibility;
	final kind:TyTypeDeclarationKind;
	final context:TyTypeResolutionContext;
	final parameterIds:Array<TyTypeParameterId>;
	final nominalArity:Null<TyNominalArity>;
	final usesBuildMacro:Bool;

	public function new(input:TyTypeDeclarationInput) {
		canonicalName = input.canonicalName;
		nominalArity = input.nominalArity;
		usesBuildMacro = input.usesBuildMacro == true;
		visibility = input.visibility;
		kind = input.kind;
		context = copyContext(input.context);
		parameterIds = switch (kind) {
			case Nominal(_): [];
			case Alias(source):
				final result = new Array<TyTypeParameterId>();
				final names = new haxe.ds.StringMap<Bool>();
				for (parameter in source.getParameters()) {
					if (names.exists(parameter.name))
						throw new TyperError(context.filePath, parameter.pos, "Duplicate type parameter name: " + parameter.name);
					names.set(parameter.name, true);
					result.push(new TyTypeParameterId("typedef:" + canonicalName, result.length, parameter.name));
				}
				result;
		};
	}

	public function getCanonicalName():String
		return canonicalName;

	public function getShortName():String
		return canonicalName.substr(canonicalName.lastIndexOf(".") + 1);

	public function getVisibility():HxVisibility
		return visibility;

	public function getKind():TyTypeDeclarationKind
		return kind;

	public function getModulePath():String
		return context.modulePath;

	public function getContext():TyTypeResolutionContext
		return copyContext(context);

	/** Type-argument counts for a nominal declaration; null for an alias or an unknown header. **/
	public function getNominalArity():Null<TyNominalArity>
		return nominalArity;

	/** Whether `@:build`, `@:autoBuild` or `@:genericBuild` can change this declaration's members. **/
	public function getUsesBuildMacro():Bool
		return usesBuildMacro;

	/** Exact alias binders are available with the header, before target resolution. */
	public function getParameterIds():Array<TyTypeParameterId>
		return parameterIds.copy();

	static function copyContext(value:TyTypeResolutionContext):TyTypeResolutionContext {
		return {
			packagePath: value.packagePath,
			modulePath: value.modulePath,
			directives: value.directives.copy(),
			filePath: value.filePath,
			position: value.position,
			parameters: value.parameters.copy()
		};
	}
}
