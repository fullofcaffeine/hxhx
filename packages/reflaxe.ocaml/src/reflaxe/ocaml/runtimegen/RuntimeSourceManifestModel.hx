package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime || eval)
/** One hashed source file owned by a runtime module. **/
typedef RuntimeSourceFile = {
	final path:String;
	final sha256:String;
	final bytes:Int;
}

/** One validated runtime module and its direct checked dependencies. **/
typedef RuntimeSourceModule = {
	final module:String;
	final scope:String;
	final files:Array<RuntimeSourceFile>;
	final dependencies:Array<String>;
	final duneLibraries:Array<String>;
	final profiles:Array<String>;
	final license:String;
}

/** Path-free, immutable view of the checked runtime source catalog. **/
typedef RuntimeSourceManifestSnapshot = {
	final schemaVersion:Int;
	final model:String;
	final runtimeVersion:String;
	final revision:String;
	final modules:Array<RuntimeSourceModule>;
}
#end
