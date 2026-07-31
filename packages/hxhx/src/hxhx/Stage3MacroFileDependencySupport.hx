package hxhx;

import CompilerMacroFileDependencyInput;
import CompilerMacroFileDependencyObservation;
import hxhx.macro.MacroState;

/**
	Seals explicit macro-to-file registrations into privacy-safe core facts.

	`MacroState` keeps the raw path only for the current request. This coordinator
	resolves it against the request working directory, observes exact bytes or a
	closed missing/not-file state, and returns only path/content digests grouped by
	the declared owning Haxe module.
**/
class Stage3MacroFileDependencySupport {
	public static function collect(cwd:String):haxe.ds.StringMap<CompilerMacroFileDependencyObservation> {
		final inputsByModule = new haxe.ds.StringMap<Array<CompilerMacroFileDependencyInput>>();
		for (registration in MacroState.listModuleDependencies()) {
			final modulePath = StringTools.trim(registration.modulePath == null ? "" : registration.modulePath);
			final rawPath = StringTools.trim(registration.externFile == null ? "" : registration.externFile);
			if (modulePath.length == 0 || rawPath.length == 0)
				continue;
			final resolvedPath = Stage3PathSupport.absFromCwd(cwd, rawPath);
			final input = observe(modulePath, resolvedPath);
			final inputs = inputsByModule.get(modulePath);
			if (inputs == null)
				inputsByModule.set(modulePath, [input]);
			else
				inputs.push(input);
		}

		final observations = new haxe.ds.StringMap<CompilerMacroFileDependencyObservation>();
		for (modulePath in inputsByModule.keys())
			observations.set(modulePath, new CompilerMacroFileDependencyObservation(inputsByModule.get(modulePath)));
		return observations;
	}

	static function observe(modulePath:String, resolvedPath:String):CompilerMacroFileDependencyInput {
		try {
			if (!sys.FileSystem.exists(resolvedPath))
				return CompilerMacroFileDependencyInput.fromObservedPath(resolvedPath, CompilerMacroFileDependencyInput.MISSING_STATE, null);
			if (sys.FileSystem.isDirectory(resolvedPath))
				return CompilerMacroFileDependencyInput.fromObservedPath(resolvedPath, CompilerMacroFileDependencyInput.NOT_FILE_STATE, null);
			return CompilerMacroFileDependencyInput.fromObservedPath(resolvedPath, CompilerMacroFileDependencyInput.FILE_STATE,
				sys.io.File.getBytes(resolvedPath));
		} catch (_:haxe.io.Error) {
			throw "could not observe a macro-registered file dependency for module: " + modulePath;
		} catch (_:haxe.Exception) {
			throw "could not observe a macro-registered file dependency for module: " + modulePath;
		} catch (_:String) {
			throw "could not observe a macro-registered file dependency for module: " + modulePath;
		}
	}
}
