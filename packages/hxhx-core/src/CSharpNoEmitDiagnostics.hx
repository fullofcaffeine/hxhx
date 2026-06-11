import haxe.io.Path;

/**
	Target-specific C# diagnostics for Stage3 source/native compile-fail lanes.

	Why
	- Upstream C# workloads include target-specific declaration errors that happen
	  before C# source packaging. If Stage3 lets the source backend run first, users
	  see an unrelated "missing static main" or packaging error instead of the
	  Haxe diagnostic the compile-fail harness is checking.

	What
	- Scans parsed source text for the currently reached C# metadata placement
	  rules and generic-constraint incompatibility shapes.
	- Returns Haxe-style diagnostic text, or `null` when no C# diagnostic applies.

	How
	- This is deliberately source-level and narrow. The bootstrap AST does not yet
	  model every C# target metadata/constraint detail, so the validator reads
	  declaration lines directly and reports the same declaration spans that the
	  C# compile-fail fixtures expect.
**/
class CSharpNoEmitDiagnostics {
	public static function diagnosticForResolved(resolved:Array<ResolvedModule>):Null<String> {
		if (resolved == null)
			return null;
		final diagnostics = new Array<String>();
		for (module in resolved) {
			if (module == null)
				continue;
			appendUsingMetadataDiagnostics(ResolvedModule.getParsed(module), diagnostics);
			appendAssemblyMetadataDiagnostics(ResolvedModule.getParsed(module), diagnostics);
		}
		for (module in resolved) {
			if (module == null)
				continue;
			appendIncompatibleConstraintDiagnostics(ResolvedModule.getParsed(module), diagnostics);
		}
		return diagnostics.length == 0 ? null : diagnostics.join("\n");
	}

	public static function diagnosticForParsed(parsed:ParsedModule):Null<String> {
		final diagnostics = new Array<String>();
		appendUsingMetadataDiagnostics(parsed, diagnostics);
		appendAssemblyMetadataDiagnostics(parsed, diagnostics);
		appendIncompatibleConstraintDiagnostics(parsed, diagnostics);
		return diagnostics.length == 0 ? null : diagnostics.join("\n");
	}

	public static function incompatibleConstraintDiagnosticForResolved(resolved:Array<ResolvedModule>):Null<String> {
		return diagnosticForResolved(resolved);
	}

	public static function incompatibleConstraintDiagnosticForParsed(parsed:ParsedModule):Null<String> {
		return diagnosticForParsed(parsed);
	}

	static function appendUsingMetadataDiagnostics(parsed:ParsedModule, diagnostics:Array<String>):Void {
		if (parsed == null)
			return;
		final source = parsed.getSource();
		if (source == null || source.length == 0 || source.indexOf("@:cs.using") < 0)
			return;
		final lines = source.split("\n");
		var seenType = false;
		for (idx in 0...lines.length) {
			final line = lines[idx];
			final trimmed = StringTools.trim(line);
			if (isTypeDeclarationLine(trimmed)) {
				seenType = true;
				continue;
			}
			if (seenType && line.indexOf("@:cs.using") >= 0 && nextSignificantTypeLineIndex(lines, idx) >= 0) {
				diagnostics.push(usingMetadataDiagnostic(parsed.getFilePath(), idx + 1, line));
			}
		}
	}

	static function appendAssemblyMetadataDiagnostics(parsed:ParsedModule, diagnostics:Array<String>):Void {
		if (parsed == null)
			return;
		final source = parsed.getSource();
		if (source == null || source.length == 0 || source.indexOf("@:cs.assembly") < 0)
			return;
		final lines = source.split("\n");
		final isTopLevelModule = !hasNamedPackage(lines);
		var seenType = false;
		for (idx in 0...lines.length) {
			final line = lines[idx];
			final trimmed = StringTools.trim(line);
			if (isTypeDeclarationLine(trimmed)) {
				seenType = true;
				continue;
			}
			final typeLineIndex = nextSignificantTypeLineIndex(lines, idx);
			if (line.indexOf("@:cs.assemblyMeta") >= 0 && typeLineIndex >= 0 && isTopLevelModule) {
				diagnostics.push(assemblyMetadataDiagnostic(parsed.getFilePath(), typeLineIndex + 1, lines[typeLineIndex],
					"@:cs.assemblyMeta cannot be used on top level modules"));
			}
			if (line.indexOf("@:cs.assemblyStrict") >= 0 && typeLineIndex >= 0) {
				if (seenType)
					diagnostics.push(assemblyMetadataDiagnostic(parsed.getFilePath(), typeLineIndex + 1, lines[typeLineIndex],
						"@:cs.assemblyStrict can only be used on the first class of a module"));
				if (isTopLevelModule)
					diagnostics.push(assemblyMetadataDiagnostic(parsed.getFilePath(), typeLineIndex + 1, lines[typeLineIndex],
						"@:cs.assemblyStrict cannot be used on top level modules"));
			}
		}
	}

	static function hasNamedPackage(lines:Array<String>):Bool {
		for (line in lines) {
			final trimmed = StringTools.trim(line);
			if (trimmed.length == 0 || StringTools.startsWith(trimmed, "//"))
				continue;
			if (!StringTools.startsWith(trimmed, "package"))
				return false;
			return trimmed != "package;" && trimmed.length > "package".length + 1;
		}
		return false;
	}

	static function nextSignificantTypeLineIndex(lines:Array<String>, metadataIndex:Int):Int {
		var idx = metadataIndex + 1;
		while (idx < lines.length) {
			final trimmed = StringTools.trim(lines[idx]);
			if (trimmed.length == 0 || StringTools.startsWith(trimmed, "//")) {
				idx++;
				continue;
			}
			if (StringTools.startsWith(trimmed, "@:")) {
				idx++;
				continue;
			}
			return isTypeDeclarationLine(trimmed) ? idx : -1;
		}
		return -1;
	}

	static function isTypeDeclarationLine(trimmed:String):Bool {
		return StringTools.startsWith(trimmed, "class ")
			|| StringTools.startsWith(trimmed, "enum ")
			|| StringTools.startsWith(trimmed, "abstract ")
			|| StringTools.startsWith(trimmed, "typedef ")
			|| StringTools.startsWith(trimmed, "interface ");
	}

	static function assemblyMetadataDiagnostic(filePath:String, lineNumber:Int, line:String, message:String):String {
		final trimmed = StringTools.trim(line);
		final startColumn = line.indexOf(trimmed) + 1;
		final endColumn = line.length + 1;
		return diagnosticPath(filePath) + ":" + Std.string(lineNumber) + ": characters " + Std.string(startColumn) + "-" + Std.string(endColumn) + " : "
			+ message;
	}

	static function usingMetadataDiagnostic(filePath:String, lineNumber:Int, line:String):String {
		final marker = "@:cs.using";
		final startColumn = line.indexOf(marker) + 1;
		final endColumn = startColumn + marker.length;
		return diagnosticPath(filePath)
			+ ":"
			+ Std.string(lineNumber)
			+ ": characters "
			+ Std.string(startColumn)
			+ "-"
			+ Std.string(endColumn)
			+ " : @:cs.using can only be used on the first type of a module";
	}

	static function appendIncompatibleConstraintDiagnostics(parsed:ParsedModule, diagnostics:Array<String>):Void {
		if (parsed == null)
			return;
		final source = parsed.getSource();
		if (source == null || source.length == 0)
			return;
		final lines = source.split("\n");
		for (idx in 0...lines.length) {
			final diagnostic = incompatibleConstraintDiagnosticForLine(parsed.getFilePath(), lines[idx], idx + 1);
			if (diagnostic != null)
				diagnostics.push(diagnostic);
		}
	}

	static function incompatibleConstraintDiagnosticForLine(filePath:String, line:String, lineNumber:Int):Null<String> {
		if (line == null || line.indexOf("class ") < 0 || line.indexOf("<") < 0 || line.indexOf(">") < 0)
			return null;
		final hasStruct = line.indexOf("CsStruct") >= 0;
		final hasClass = line.indexOf("CsClass") >= 0;
		final hasUnmanaged = line.indexOf("CsUnmanaged") >= 0;
		final hasConstructible = line.indexOf("Constructible") >= 0;
		if (!hasStruct && !hasClass && !hasUnmanaged && !hasConstructible)
			return null;
		final message = if (hasStruct && hasConstructible) {
			"The new() constraint cannot be combined with the struct constraint.";
		} else if (hasStruct && hasClass) {
			"The class constraint cannot be combined with the struct constraint.";
		} else if (hasStruct && hasUnmanaged) {
			"The unmanaged constraint cannot be combined with the struct constraint.";
		} else if (hasUnmanaged && hasConstructible) {
			"The unmanaged constraint cannot be combined with the new() constraint.";
		} else {
			return null;
		}
		final startColumn = line.indexOf("class ") + 1;
		final endColumn = line.length + 1;
		return diagnosticFileName(filePath) + ":" + Std.string(lineNumber) + ": characters " + Std.string(startColumn) + "-" + Std.string(endColumn) + " : "
			+ message;
	}

	static function diagnosticFileName(filePath:String):String {
		if (filePath == null || filePath.length == 0)
			return "<unknown>";
		return Path.withoutDirectory(filePath);
	}

	static function diagnosticPath(filePath:String):String {
		if (filePath == null || filePath.length == 0)
			return "<unknown>";
		final normalizedPath = Path.normalize(filePath);
		final normalizedCwd = Path.normalize(Sys.getCwd());
		if (StringTools.startsWith(normalizedPath, normalizedCwd)) {
			var relativePath = normalizedPath.substr(normalizedCwd.length);
			if (StringTools.startsWith(relativePath, "/"))
				relativePath = relativePath.substr(1);
			if (relativePath.length > 0)
				return relativePath;
		}
		return normalizedPath;
	}
}
