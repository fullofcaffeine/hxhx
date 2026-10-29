import backend.ocaml.HxhxOcamlTargetDeclarationAdapter;
import ClassMarkerObservation.describeRequirements;
import backend.ocaml.HxhxOcamlTargetClassMarkerAdapter.fromTypedClass;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.lowered.OcamlClassIdentityMarkerPlan;
import reflaxe.ocaml.target.OcamlTargetClassMarker.lowerClassMarker;
import sys.io.File;

/** Keep class construction eligibility distinct before the shared target selects a layout. */
class SharedClassKindsFixture {
	static function main():Void {
		final path = "test/reflaxe_ocaml_shared_instance_values/source/ClassKinds.hx";
		final resolved = new ResolvedModule("ClassKinds", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final revision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		final request = HxhxOcamlTargetDeclarationAdapter.fromModules(revision, [typed.getBackendProjection()]);
		final stock = StockClassKindsMacro.expected();
		var compared = 0;
		for (cls in request.copyClasses()) {
			final expectedInterface = cls.canonicalIdentity == "ClassKinds#Contract"
				|| cls.canonicalIdentity == "ClassKinds#ChildContract";
			final expectedExtern = cls.canonicalIdentity == "ClassKinds#External";
			final expectedParents = cls.canonicalIdentity == "ClassKinds#Implementation"
				|| cls.canonicalIdentity == "ClassKinds#ChildContract";
			if (cls.isInterface != expectedInterface
				|| cls.isExtern != expectedExtern
				|| cls.copyInterfaceTypeDisplays().length != (expectedParents ? 1 : 0))
				throw "authored class role or applied interface was lost for " + cls.canonicalIdentity;
			if (expectedParents && cls.copyInterfaceTypeDisplays()[0] != "ClassKinds.Contract<Int>")
				throw "applied interface argument changed for " + cls.canonicalIdentity + ": " + cls.copyInterfaceTypeDisplays()[0];
			final matches = stock.filter(row -> row.name == cls.canonicalIdentity);
			if (matches.length != 1
				|| matches[0].identity != cls.getCanonicalIdentity()
				|| matches[0].isInterface != cls.isInterface
				|| matches[0].isExtern != cls.isExtern
				|| matches[0].interfaces != cls.copyInterfaceTypeDisplays().join("|")) {
				final facts = new Array<Null<String>>();
				cls.addIdentity(facts);
				throw "class declarations differ between hosts for " + cls.canonicalIdentity + " stock="
					+ (matches.length == 1 ? matches[0].facts : "missing") + " native=" + haxe.Json.stringify(facts);
			}
			compared++;
		}
		if (compared != 5
			|| stock.length != compared
			|| CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != revision)
			throw "class-header inventory or original module revision changed";
		final stockMarkers = StockClassKindsMacro.markers();
		var markerCount = 0;
		for (typedClass in typed.getTypedClasses()) {
			for (role in [
				OcamlClassIdentityMarkerPlan.CONSTRUCTOR_ROLE,
				OcamlClassIdentityMarkerPlan.EMPTY_INSTANCE_ROLE
			]) {
				final marker = fromTypedClass({
					module: typed,
					typedClass: typedClass,
					emissionRole: role,
					programRevision: "class-headers-program",
					pipelineRevision: "class-headers-pipeline"
				});
				final expected = stockMarkers.filter(row -> row.name == marker.sourceDeclarationId && row.role == role);
				final lowered = lowerClassMarker(marker, "portable");
				final syntax = new OcamlASTPrinter().printExpr(lowered.expression);
				if (expected.length != 1
					|| expected[0].id != marker.id
					|| expected[0].revision != marker.revision
					|| expected[0].file != marker.source.file
					|| expected[0].start != marker.source.min
					|| expected[0].end != marker.source.max
					|| expected[0].syntax != syntax
					|| expected[0].requirements != describeRequirements(lowered.runtimeRequirements))
					throw "class marker differs between hosts for " + marker.sourceDeclarationId + " / " + role + " expected="
						+ haxe.Json.stringify(expected) + " actual=" + haxe.Json.stringify(marker) + " syntax=" + syntax + " requirements="
						+ haxe.Json.stringify(lowered.runtimeRequirements);
				markerCount++;
			}
		}
		if (markerCount != 10
			|| stockMarkers.length != markerCount
			|| CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != revision)
			throw "class-marker inventory or original module revision changed";
		final other = typeSource("OtherMarker", "class OtherMarker {}");
		expectMarkerFailure(typed, other.getTypedClasses()[0], "owned by its typed module");
		final hidden = typeSource("PrivateMarker", "private class PrivateMarker {}");
		expectMarkerFailure(hidden, hidden.getTypedClasses()[0], "private runtime names");
		final renamed = typeSource("NativeMarker", '@:native("Renamed") class NativeMarker {}');
		expectMarkerFailure(renamed, renamed.getTypedClasses()[0], "renamed runtime classes");
		final original = typeSource("OriginalMarker", '@:realPath("Original") class OriginalMarker {}');
		expectMarkerFailure(original, original.getTypedClasses()[0], "renamed runtime classes");
		Sys.println("REFLAXE_OCAML_SHARED_CLASS_HEADERS:PASS");
	}

	/** Use the real parser and typer even when testing rejected marker declarations. */
	static function typeSource(name:String, source:String):TypedModule {
		final resolved = new ResolvedModule(name, name + ".hx", ParserStage.parse(source, name + ".hx"));
		return TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
	}

	static function expectMarkerFailure(module:TypedModule, typedClass:TypedClass, message:String):Void {
		try {
			fromTypedClass({
				module: module,
				typedClass: typedClass,
				emissionRole: OcamlClassIdentityMarkerPlan.CONSTRUCTOR_ROLE,
				programRevision: "class-headers-program",
				pipelineRevision: "class-headers-pipeline"
			});
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(message) >= 0)
				return;
			throw error;
		}
		throw "invalid class marker was admitted: " + message;
	}
}
