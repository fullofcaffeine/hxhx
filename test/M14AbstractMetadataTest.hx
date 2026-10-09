/** Abstract headers keep authored metadata and binders before their bodies are enriched. */
class M14AbstractMetadataTest {
	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function main():Void {
		final metadata = [
			'@:multiType(@:followWithAbstracts T)',
			'@:probe("spaced (value)", [1, 2])',
			'@:probe("second")'
		];
		final source = metadata.join("\n")
			+
			'\nprivate abstract Choice<T>(Array<T>) { public function new(); public function after():Int return 7; }\n@:neighbor class Main { static function main():Void {} }\nabstract Plain(Int) {}';
		for (path in ["Main.hx", "Choice.hx"]) {
			final parsed = ParserStage.parse(source, path).getDecl();
			final matches = HxModuleDecl.getClasses(parsed).filter(value -> HxClassDecl.getName(value) == "Choice");
			require(matches.length == 1, "abstract declaration is missing or duplicated");
			final declaration = matches[0];
			final actual = HxClassDecl.getMetadata(declaration);
			for (value in metadata)
				require(actual.indexOf(value) >= 0, "authored abstract metadata disappeared: " + value);
			require(actual.indexOf("@:neighbor") < 0, "following class metadata entered the abstract");
			require(HxClassDecl.getVisibility(declaration) == HxVisibility.Private, "abstract visibility changed");
			require(HxClassDecl.getTypeParameters(declaration).length == 1 && HxClassDecl.getTypeParameters(declaration)[0].name == "T",
				"abstract binder syntax disappeared");
			require(HxClassDecl.getFunctions(declaration).length == 2, "abstract body enrichment lost its members");
			require(HxClassDecl.getName(HxModuleDecl.getMainClass(parsed)) == path.split(".")[0], "requested main declaration changed");
			for (other in HxModuleDecl.getClasses(parsed))
				if (other != declaration)
					for (value in metadata)
						require(HxClassDecl.getMetadata(other).indexOf(value) < 0, "abstract metadata leaked to another declaration");
		}
		for (inferred in [new HxParser(source).parseModule(), ParserStage.parse(source).getDecl()])
			require(HxClassDecl.getName(HxModuleDecl.getMainClass(inferred)) == "Main", "abstract header displaced ordinary main selection");
		final direct = new HxParser(source).parseModule("Choice");
		require(HxClassDecl.getMetadata(HxModuleDecl.getMainClass(direct)).indexOf(metadata[0]) >= 0, "main parser discarded abstract policy");
		final only = ParserStage.parse(metadata[0] + "\nabstract Choice<T>(Array<T>) { public function new(); }", "Choice.hx").getDecl();
		require(HxClassDecl.getMetadata(HxModuleDecl.getMainClass(only)).indexOf(metadata[0]) >= 0, "primary abstract metadata disappeared");
		Sys.println("ABSTRACT_METADATA:PASS");
	}
}
