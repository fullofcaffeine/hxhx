class Main {
	static function main() {
		final fs = new haxe.display.FsPath("/tmp/hxhx");
		Sys.println("fs=" + fs.toString());

		final pos:haxe.display.Position.Position = {line: 2, character: 3};
		final range:haxe.display.Position.Range = {
			start: pos,
			end: {line: 2, character: 5}
		};
		final loc:haxe.display.Position.Location = {file: fs, range: range};
		Sys.println("pos=" + loc.range.start.line + ":" + loc.range.start.character);
		Sys.println("range.end=" + loc.range.end.character);

		Sys.println("method.initialize=" + Std.string(haxe.display.Protocol.Methods.Initialize));
		Sys.println("method.completion=" + Std.string(haxe.display.Display.DisplayMethods.Completion));
		Sys.println("method.contexts=" + Std.string(haxe.display.Server.ServerMethods.Contexts));

		final severity:haxe.display.Diagnostic.DiagnosticSeverity = haxe.display.Diagnostic.DiagnosticSeverity.Warning;
		final severityInt:Int = cast severity;
		Sys.println("diag.severity=" + severityInt);

		final importStatus:haxe.display.JsonModuleTypes.ImportStatus = haxe.display.JsonModuleTypes.ImportStatus.Unimported;
		final importStatusInt:Int = cast importStatus;
		final path:haxe.display.JsonModuleTypes.JsonTypePath = {
			pack: ["demo"],
			moduleName: "Mod",
			typeName: "Type",
			importStatus: importStatus
		};
		Sys.println("importStatus=" + importStatusInt);
		Sys.println("typePath=" + path.pack[0] + "." + path.moduleName + "." + path.typeName);
	}
}
