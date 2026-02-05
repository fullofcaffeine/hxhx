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

	public function new(name:String, hasStaticMain:Bool, ?functions:Array<HxFunctionDecl>) {
		this.name = name;
		this.hasStaticMain = hasStaticMain;
		this.functions = functions == null ? [] : functions;
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
}
