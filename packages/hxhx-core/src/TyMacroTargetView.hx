/**
	How a target compile sees a macro function.

	What
	- Upstream Haxe 4.3.7 types a macro function's body only in its macro context. Every other
	  compile sees the function without a body and with a rewritten signature (`typeloadFields.ml`,
	  lines 1298-1336):
	  - an instance macro loses its first argument, which receives the `this` expression;
	  - an argument or result written `ExprOf<T>` or `haxe.macro.Expr.ExprOf<T>` becomes `T`;
	  - every other written type, and a missing one, becomes `Dynamic`;
	  - defaults are dropped, so an argument stays optional only when it is written with `?`;
	  - a type written `haxe.PosInfos` is an error.
	- The rule reads the type as written: `Null<ExprOf<T>>` and an imported bare `PosInfos` both
	  become `Dynamic`.

	How
	- `declaration` builds that bodyless declaration from the written one. In a target compile the
	  index types it as the declaration's signature (`TyDeclarationInfo.getSignature()`), and
	  `TyperStage` types it in place of the function. Call sites keep the written signature
	  (`TyDeclarationInfo.getMacroSignature()`), because a call passes syntax to the macro.
	- hxhx's macro context is the project-macro plugin build (`MacroCompilationContext`), where
	  macro functions keep their written signatures and bodies.
**/
final class TyMacroTargetView {
	public static inline final POS_INFOS_ERROR = "haxe.PosInfos is not allowed on macro functions, use Context.currentPos() instead";

	/**
		Whether a compile that does not type this module's macro bodies
		(`MacroCompilationContext.typesMacroBodies`) sees `fn`, a function of class `className` in
		`filePath`, through its target view. hxhx's own bundled-sources macro keeps its body and its
		written signature (`MacroCompilationContext.isBundledSourcesMacro`).
	**/
	public static function applies(fn:HxFunctionDecl, className:String, filePath:Null<String>):Bool {
		return HxFunctionDecl.getMetadata(fn).indexOf("macro") >= 0
			&& HxFunctionDecl.getHasBody(fn)
			&& !MacroCompilationContext.isBundledSourcesMacro(className + "." + HxFunctionDecl.getName(fn), filePath);
	}

	/** The bodyless declaration that a target compile types for the macro function `fn`. */
	public static function declaration(fn:HxFunctionDecl):HxFunctionDecl {
		final written = HxFunctionDecl.getArgs(fn);
		final args = [
			for (index in (HxFunctionDecl.getIsStatic(fn) ? 0 : 1)...written.length) {
				final arg = written[index];
				// The parser marks `...rest:T` optional; upstream's rest argument is a `haxe.Rest<T>`
				// type, so its target view is a required `Dynamic`.
				final optional = HxFunctionArg.getIsOptional(arg) && !HxFunctionArg.getIsRest(arg);
				new HxFunctionArg(HxFunctionArg.getName(arg), typeHint(HxFunctionArg.getTypeHint(arg)), HxDefaultValue.NoDefault, optional, false, "",
					HxFunctionArg.getMetadata(arg));
			}
		];
		return new HxFunctionDecl(HxFunctionDecl.getName(fn), HxFunctionDecl.getVisibility(fn), HxFunctionDecl.getIsStatic(fn), args,
			typeHint(HxFunctionDecl.getReturnTypeHint(fn)), [], "", HxFunctionDecl.getMetadata(fn), HxFunctionDecl.getPos(fn), HxFunctionDecl.getEndPos(fn),
			"", true, HxFunctionDecl.getIsModuleLevel(fn), true);
	}

	/** The written type `hint` in the target view: `T` for `ExprOf<T>`, `Dynamic` for anything else. */
	public static function typeHint(hint:Null<String>):String {
		final text = hint == null ? "" : StringTools.trim(hint);
		final parsed = TyType.fromHintText(text);
		if (parsed.isUnresolved() && parsed.getTypeArguments().length == 1) {
			final path = parsed.getUnresolvedPath();
			// The parser joins a hint's tokens, so the argument is the text between the outer `<` and `>`.
			if (path == "ExprOf" || path == "haxe.macro.Expr.ExprOf")
				return StringTools.trim(text.substring(text.indexOf("<") + 1, text.length - 1));
		}
		return "Dynamic";
	}

	/** Whether the written type `hint` is `haxe.PosInfos`, which a macro function may not declare. */
	public static function rejectsTypeHint(hint:Null<String>):Bool
		return hint != null && StringTools.trim(hint) == "haxe.PosInfos";
}
