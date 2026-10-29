package hxhx.macro;

/**
	One project expression-macro call after declaration selection and before execution.

	Why
	- The previous expansion route transported an exact call string and received
	  source text back. That route cannot carry authored argument syntax, cannot
	  name the declaration it selected, and loses positions through reparsing.
	- Executors (the in-process runtime, the external host, native plugins) need
	  one typed request so argument encoding and result decoding have a single owner.

	What
	- Retains the selected declaration, the original argument nodes in call order,
	  and the call's module facts. The declaration identity is data for executors
	  to look up; it is never a handler path to invoke by reflection.
	- Argument nodes are the authored syntax tree. They are not typed values and
	  must not be evaluated by the compiler before the macro sees them.

	How
	- `ExprMacroExpander` builds a request when `ExprMacroDeclarationSelector`
	  selects a static `macro` declaration for a call (public, or private when
	  called from its own class). The session answers with `ExprMacroDispatchResult`:
	  `Expanded` replaces the call structurally; `Unavailable` is recorded as an
	  unexecuted call, and the call continues through ordinary typing under the
	  macro call-site contract. Once a general executor exists, `Unavailable`
	  must become a compile error at the call site.
**/
class ExprMacroDispatchRequest {
	final declaration:TyDeclarationInfo;
	final arguments:Array<HxExpr>;
	final filePath:String;
	final modulePath:String;

	public function new(declaration:TyDeclarationInfo, arguments:Array<HxExpr>, filePath:String, modulePath:String) {
		if (declaration == null)
			throw "macro dispatch request requires a selected declaration";
		this.declaration = declaration;
		this.arguments = arguments == null ? [] : arguments.copy();
		this.filePath = filePath == null ? "<unknown>" : filePath;
		this.modulePath = modulePath == null ? "" : modulePath;
	}

	public function getDeclaration():TyDeclarationInfo
		return declaration;

	/** Authored argument syntax in call order; a fresh array each time, nodes shared. */
	public function getArguments():Array<HxExpr>
		return arguments.copy();

	public function getFilePath():String
		return filePath;

	public function getModulePath():String
		return modulePath;

	/** Readable `owner.method` label for diagnostics; not a lookup key. */
	public function describe():String
		return declaration.getOwner().getCanonicalName() + "." + declaration.getSignature().getName();
}

/** Executors distinguish a structured expansion from an explicit inability to run the selected macro. */
enum ExprMacroDispatchResult {
	/** The macro produced this syntax; the caller inserts it in place of the call. */
	Expanded(expression:HxExpr);

	/** No executor can run this declaration in the current session; the reason is user-facing. */
	Unavailable(reason:String);
}
