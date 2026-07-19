package reflaxe.ocaml.tooling;

/** Closed options accepted by the source-to-native authoring loop. **/
typedef AuthoringBuildOptions = {
	final hxmlPath:String;
	final outputPath:String;
	final watch:Bool;
	final watchPaths:Array<String>;
	final pollMilliseconds:Int;
	final debounceMilliseconds:Int;
	final maxBuilds:Null<Int>;
	final runArtifact:Null<String>;
	final runArguments:Array<String>;
}
