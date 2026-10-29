package backend.source;

/**
	Decide which exact static calls the Python source target can execute.

	Why: Python emits classes only from non-library modules. A static call to a
	standard-library class is rendered as `Owner.method(...)`, which works only
	when the Python runtime prelude or a support template defines that member,
	or when the renderer lowers the call itself. Any other such call used to
	compile and then fail at run time with a `NameError` or `AttributeError`,
	for example `Std.downcast(v, B)` or `Type.createInstance(c, [])`, whatever
	the argument expression was.

	What: a call is admitted when its typed owner is a class Python emits (see
	`SourceTargetCommon.pythonEmittedClassName`) or when the owner and method
	appear in the explicit table below. Every other call is a compiler error
	before output. `Std.isOfType` is lowered by `PythonRuntimeTypeLowering`.

	Keep the table in step with `source-templates/python/runtime/Prelude.py`,
	`source-templates/python/support/*.py`, and the renderer's own lowerings.
**/
class PythonStaticCallAdmission {
	/** Library static members the Python runtime or renderer implements, by canonical owner. */
	static function supportedMembers(owner:String):Array<String> {
		return switch (owner) {
			// The renderer lowers Std.string; Std.isOfType is lowered from typed facts.
			case "Std": ["string", "isOfType"];
			case "Sys": ["println", "environment", "systemName", "exit"];
			case "haxe.Timer": ["stamp"];
			case "Type": [
					"resolveClass",
					"getClass",
					"getClassName",
					"getInstanceFields",
					"getClassFields"
				];
			case "Reflect": ["field", "getProperty", "isFunction", "isObject", "compare"];
			case "StringTools": ["startsWith", "endsWith", "hex"];
			case "DateTools": ["seconds", "minutes", "hours", "days"];
			case "haxe.ds.Vector": ["fromArrayCopy"];
			case "haxe.rtti.Meta": ["getFields", "getStatics", "getType"];
			case "haxe.macro.Compiler": ["getDefine", "define", "excludeFile"];
			case _: [];
		};
	}

	final renderedOwners:haxe.ds.StringMap<Bool>;

	/** @param renderedOwners Canonical identities of classes whose static functions Python emits. */
	public function new(renderedOwners:haxe.ds.StringMap<Bool>) {
		this.renderedOwners = renderedOwners;
	}

	/** Reject an exact static call Python cannot execute; other expressions are ignored. */
	public function check(original:HxExpr):Void {
		final call = TypedExactStaticCallSource.decode(original);
		if (call == null || renderedOwners.exists(call.owner) || supportedMembers(call.owner).indexOf(call.method) >= 0)
			return;
		throw "Python source target does not support the standard-library call " + call.owner + "." + call.method;
	}
}
