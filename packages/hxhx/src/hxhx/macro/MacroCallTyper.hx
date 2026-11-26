package hxhx.macro;

/** The call site's typer and loader: `Context.typeof` types code at the call's module and class. */
typedef MacroCallTyper = {
	final context:TyperContext;
	final loader:Null<ModuleLoader>;
}
