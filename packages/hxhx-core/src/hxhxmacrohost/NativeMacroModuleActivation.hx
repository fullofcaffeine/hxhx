package hxhxmacrohost;

/** Validated identity and file location for one loadable project-macro plugin. **/
typedef NativeMacroModuleActivation = {
	final candidateCommit:String;
	final pluginId:String;
	final expressions:Array<String>;
	final artifactKind:String;
	final artifactPath:String;
	final artifactSha256:String;
}
