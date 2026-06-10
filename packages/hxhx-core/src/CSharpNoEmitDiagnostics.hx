import haxe.io.Path;

/**
	Target-specific C# diagnostics for Stage3 source/native compile-fail lanes.

	Why
	- Upstream C# workloads include target-specific declaration errors that happen
	  before C# source packaging. If Stage3 lets the source backend run first, users
	  see an unrelated "missing static main" or packaging error instead of the
	  Haxe diagnostic the compile-fail harness is checking.

	What
	- Scans parsed source text for the currently reached C# generic-constraint
	  incompatibility shapes.
	- Returns Haxe-style diagnostic text, or `null` when no C# diagnostic applies.

	How
	- This is deliberately source-level and narrow. The bootstrap AST does not yet
	  model class type-parameter constraints, so the validator reads declaration
	  lines directly and reports the whole class declaration range.
**/
class CSharpNoEmitDiagnostics {
	public static function incompatibleConstraintDiagnosticForResolved(resolved:Array<ResolvedModule>):Null<String> {
		if (resolved == null)
			return null;
		final diagnostics = new Array<String>();
		for (module in resolved) {
			if (module == null)
				continue;
			appendIncompatibleConstraintDiagnostics(ResolvedModule.getParsed(module), diagnostics);
		}
		return diagnostics.length == 0 ? null : diagnostics.join("\n");
	}

	public static function incompatibleConstraintDiagnosticForParsed(parsed:ParsedModule):Null<String> {
		final diagnostics = new Array<String>();
		appendIncompatibleConstraintDiagnostics(parsed, diagnostics);
		return diagnostics.length == 0 ? null : diagnostics.join("\n");
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
}
