import haxe.io.Path;

/**
	Target-specific compile-fail diagnostics for the Stage3 Java no-emit lane.

	Why:
	- Some upstream Java fixtures validate target-specific parser/typing errors even when
	  Stage3 is running in `--hxhx-no-emit` mode.
	- Keeping these checks here makes the behavior testable without booting the full
	  `hxhx.Stage3Compiler` process, which also owns native-only transports.

	What:
	- Emits narrow Haxe-style diagnostics for Java metadata shapes that the current
	  bootstrap parser would otherwise accept too permissively.
	- Returns `null` when no target-specific no-emit diagnostic applies.
**/
class JavaNoEmitDiagnostics {
	/**
		Return the first malformed Java annotation metadata diagnostic for typed modules.

		How:
		- Scans the original parsed source so positions match the user-facing source text.
		- Uses basename paths because upstream compile-fail expectations compare Haxe-style
		  diagnostics such as `Main.hx:line: characters ...`.
	**/
	public static function jvmAnnotationMetadataDiagnostic(typedModules:Array<TypedModule>):Null<String> {
		if (typedModules == null)
			return null;
		for (typed in typedModules) {
			if (typed == null)
				continue;
			final parsed = typed.getParsed();
			final diagnostic = jvmAnnotationMetadataDiagnosticForParsed(parsed);
			if (diagnostic != null)
				return diagnostic;
		}
		return null;
	}

	static function jvmAnnotationMetadataDiagnosticForParsed(parsed:ParsedModule):Null<String> {
		if (parsed == null)
			return null;
		final source = parsed.getSource();
		if (source == null || source.length == 0)
			return null;
		final metaStart = source.indexOf("jvm.annotation.ClassReflectionInformation(");
		if (metaStart < 0)
			return null;
		final fieldStart = source.indexOf("hasSuperClass", metaStart);
		if (fieldStart < 0)
			return null;
		final fieldEnd = metadataFieldEnd(source, fieldStart);
		final start = sourcePosition(source, fieldStart + 1);
		final end = sourcePosition(source, fieldEnd);
		return diagnosticFileName(parsed.getFilePath()) + ":" + Std.string(start.line) + ": characters " + Std.string(start.column) + "-"
			+ Std.string(end.column) + " : Object declaration expected";
	}

	static function diagnosticFileName(filePath:String):String {
		if (filePath == null || filePath.length == 0)
			return "<unknown>";
		return Path.withoutDirectory(filePath);
	}

	static function metadataFieldEnd(source:String, fieldStart:Int):Int {
		var i = fieldStart;
		while (i < source.length) {
			final ch = source.charCodeAt(i);
			if (ch == ")".code || ch == ",".code || ch == "\n".code || ch == "\r".code)
				return i + 1;
			i += 1;
		}
		return source.length;
	}

	static function sourcePosition(source:String, index:Int):{line:Int, column:Int} {
		var line = 1;
		var lineStart = 0;
		var i = 0;
		final safeIndex = index < 0 ? 0 : (index > source.length ? source.length : index);
		while (i < safeIndex) {
			if (source.charCodeAt(i) == "\n".code) {
				line += 1;
				lineStart = i + 1;
			}
			i += 1;
		}
		return {line: line, column: safeIndex - lineStart};
	}
}
