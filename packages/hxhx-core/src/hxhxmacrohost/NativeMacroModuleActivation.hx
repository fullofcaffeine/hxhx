package hxhxmacrohost;

/** Validated identity and file location for one loadable project-macro plugin. **/
typedef NativeMacroModuleActivation = {
	/** The cache key the receipt was validated against (see `NativeMacroModuleReceipt`). */
	final cacheKey:String;

	final pluginId:String;
	final declarations:Array<String>;
	final artifactKind:String;
	final artifactPath:String;
	final artifactSha256:String;
}
