/**
	Class declaration AST node for the Haxe-in-Haxe compiler bring-up.

	Why:
	- In the early bootstrapping stages we primarily need a reliable module name
	  and an entrypoint signal ("does this module define a static main?").

	What:
	- Class name.
	- Whether a 'static function main' exists in the class body.
**/
class HxClassDecl {
	public final name:String;
	public final hasStaticMain:Bool;
	public final functions:Array<HxFunctionDecl>;
	public final fields:Array<HxFieldDecl>;
	public final extendsPath:String;
	public final metadata:Array<String>;
	public final isInterface:Bool;
	public final implementsPaths:Array<String>;
	public final visibility:HxVisibility;

	public function new(name:String, hasStaticMain:Bool, ?functions:Array<HxFunctionDecl>, ?fields:Array<HxFieldDecl>, ?extendsPath:String,
			?metadata:Array<String>, ?isInterface:Bool, ?implementsPaths:Array<String>, ?visibility:HxVisibility) {
		this.name = name;
		this.hasStaticMain = hasStaticMain;
		this.functions = functions == null ? [] : functions;
		this.fields = fields == null ? [] : fields;
		this.extendsPath = extendsPath == null ? "" : extendsPath;
		this.metadata = metadata == null ? [] : metadata;
		this.isInterface = isInterface == null ? false : isInterface;
		this.implementsPaths = implementsPaths == null ? [] : implementsPaths;
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

	public static function getIsInterface(c:HxClassDecl):Bool {
		return c.isInterface;
	}

	public static function getImplementsPaths(c:HxClassDecl):Array<String> {
		return c.implementsPaths;
	}

	/** Whether another module may import this top-level type. **/
	public static function getVisibility(c:HxClassDecl):HxVisibility
		return c.visibility;
}
