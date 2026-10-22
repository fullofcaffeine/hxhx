/**
	The authored keyword-to-closing-brace range of a class or interface.

	Offsets count Unicode code points, as upstream Haxe positions do. The lexer
	uses host string indices, which can count bytes or UTF-16 units instead.
	The parser normalizes that difference before storing this immutable range.
	The end points immediately after the closing brace, before trailing trivia.
**/
typedef HxClassSourceRange = {
	final start:Int;
	final end:Int;
}

/**
	Parsed class or interface header and its declared members.

	A class has at most one superclass. An interface can extend several other
	interfaces. Those parents remain separate so constructor traversal cannot
	consume interface membership edges. All paths are source names until typing
	selects their declarations.
**/
class HxClassDecl {
	public final name:String;
	public final hasStaticMain:Bool;
	public final functions:Array<HxFunctionDecl>;
	public final fields:Array<HxFieldDecl>;
	public final extendsPath:String;
	public final metadata:Array<String>;
	public final isInterface:Bool;
	public final isExtern:Bool;
	public final implementsPaths:Array<String>;
	public final interfaceExtendsPaths:Array<String>;
	public final visibility:HxVisibility;
	public final enumDeclaration:Null<HxEnumDeclaration>;

	final typeParameters:Array<HxTypeSyntax.HxTypeSyntaxParameter>;
	final sourceRange:Null<HxClassSourceRange>;

	public function new(name:String, hasStaticMain:Bool, ?functions:Array<HxFunctionDecl>, ?fields:Array<HxFieldDecl>, ?extendsPath:String,
			?metadata:Array<String>, ?isInterface:Bool, ?implementsPaths:Array<String>, ?visibility:HxVisibility, ?interfaceExtendsPaths:Array<String>,
			isExtern:Bool = false, ?enumDeclaration:HxEnumDeclaration, ?typeParameters:Array<HxTypeSyntax.HxTypeSyntaxParameter>,
			?sourceRange:HxClassSourceRange) {
		this.name = name;
		this.hasStaticMain = hasStaticMain;
		this.functions = functions == null ? [] : functions;
		this.fields = fields == null ? [] : fields;
		this.extendsPath = extendsPath == null ? "" : extendsPath;
		this.metadata = metadata == null ? [] : metadata;
		this.isInterface = isInterface == null ? false : isInterface;
		this.isExtern = isExtern;
		this.enumDeclaration = enumDeclaration;
		this.typeParameters = typeParameters == null ? [] : HxTypeSyntax.copyParameters(typeParameters);
		if (sourceRange != null && (sourceRange.start < 0 || sourceRange.end <= sourceRange.start))
			throw "class source range requires ordered Unicode source offsets";
		this.sourceRange = sourceRange == null ? null : {start: sourceRange.start, end: sourceRange.end};
		this.implementsPaths = implementsPaths == null ? [] : implementsPaths;
		this.interfaceExtendsPaths = interfaceExtendsPaths == null ? [] : interfaceExtendsPaths.copy();
		if (this.isInterface && this.extendsPath.length > 0)
			throw "interface parents must not occupy the superclass path";
		if (!this.isInterface && this.interfaceExtendsPaths.length > 0)
			throw "class interfaces must use implements paths";
		this.visibility = visibility == null ? HxVisibility.Public : visibility;
	}

	/**
		Non-inline getter for `name`.

		See `HxModuleDecl.getPackagePath` for why we prefer getters in the example:
		it keeps dune `-opaque` builds happy while we bootstrap.
	**/
	public static function getName(c:HxClassDecl):String {
		return c.name;
	}

	/** Preserve authored class bounds as syntax; typing resolves them in the declaring module. */
	public static function getTypeParameters(c:HxClassDecl):Array<HxTypeSyntax.HxTypeSyntaxParameter>
		return HxTypeSyntax.copyParameters(c.typeParameters);

	/**
		Return the actual parsed class range for diagnostics and runtime ownership.

		Synthetic declarations and declaration kinds without a parsed range retain
		absence. Callers must not turn that absence into a successful source claim.
	**/
	public static function getSourceRange(c:HxClassDecl):Null<HxClassSourceRange>
		return c.sourceRange;

	/**
		Non-inline getter for `hasStaticMain`.
	**/
	public static function getHasStaticMain(c:HxClassDecl):Bool {
		return c.hasStaticMain;
	}

	/**
		Non-inline getter for `functions`.
	**/
	public static function getFunctions(c:HxClassDecl):Array<HxFunctionDecl> {
		return c.functions;
	}

	/**
		Non-inline getter for parsed fields.
	**/
	public static function getFields(c:HxClassDecl):Array<HxFieldDecl> {
		return c.fields;
	}

	/**
		Returns the source-level superclass path when the bootstrap parser can
		observe one.

		The Stage3 JS backend uses this only as behavior metadata for prototype
		chaining and constructor ordering; unresolved paths remain empty instead
		of weakening parser errors elsewhere.
	**/
	public static function getExtendsPath(c:HxClassDecl):String {
		return c.extendsPath;
	}

	public static function getMetadata(c:HxClassDecl):Array<String> {
		return c.metadata;
	}

	/** Extern declarations describe target-owned values rather than generated definitions. */
	public static function getIsExtern(c:HxClassDecl):Bool
		return c.isExtern;

	/** Only parsed enum syntax supplies this inventory; class members cannot imitate it. */
	public static function getEnumDeclaration(c:HxClassDecl):Null<HxEnumDeclaration>
		return c.enumDeclaration;

	public static function getIsInterface(c:HxClassDecl):Bool {
		return c.isInterface;
	}

	public static function getImplementsPaths(c:HxClassDecl):Array<String> {
		return c.implementsPaths;
	}

	/** Interface parents in source order, separate from a class constructor parent. */
	public static function getInterfaceExtendsPaths(c:HxClassDecl):Array<String>
		return c.interfaceExtendsPaths.copy();

	/** Whether another module may import this top-level type. **/
	public static function getVisibility(c:HxClassDecl):HxVisibility
		return c.visibility;
}
