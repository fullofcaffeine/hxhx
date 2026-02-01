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

	public function new(name:String, hasStaticMain:Bool) {
		this.name = name;
		this.hasStaticMain = hasStaticMain;
	}
}

