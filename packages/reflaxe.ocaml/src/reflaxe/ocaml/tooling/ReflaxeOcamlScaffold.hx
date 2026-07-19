package reflaxe.ocaml.tooling;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

using StringTools;

private typedef ScaffoldTemplateFile = {
	final relativePath:String;
	final contents:String;
}

/**
	Creates package-owned starter projects through an all-or-nothing directory copy.

	Only application and library layouts are currently admitted. Binding, adapter,
	and plugin projects need typed manifests owned by their respective architecture
	work and are rejected before any destination is created.
**/
class ReflaxeOcamlScaffold {
	static inline final STAGING_SUFFIX = ".reflaxe-ocaml-new";

	/** Validates, renders, and atomically renames one scaffold into place. **/
	public static function create(packageRoot:String, invocationRoot:String, kind:String, destination:String, projectName:Null<String>):ScaffoldResult {
		final normalizedKind = kind.trim().toLowerCase();
		final unsupported = unsupportedKindMessage(normalizedKind);
		if (unsupported != null) {
			return Rejected(unsupported);
		}
		if (normalizedKind != "app" && normalizedKind != "library") {
			return Rejected('Unknown scaffold kind "$kind". Supported kinds are app and library.');
		}
		if (destination.trim().length == 0) {
			return Rejected("The scaffold destination cannot be empty.");
		}

		var targetRoot = absoluteFrom(invocationRoot, destination);
		if (FileSystem.exists(targetRoot)) {
			return Rejected('Destination already exists; no files were changed: $targetRoot');
		}
		final parent = Path.directory(targetRoot);
		if (parent.length == 0 || !FileSystem.exists(parent) || !FileSystem.isDirectory(parent)) {
			return Rejected('Destination parent directory does not exist: $parent');
		}
		try {
			targetRoot = Path.join([FileSystem.fullPath(parent), Path.withoutDirectory(targetRoot)]);
		} catch (error:Dynamic) {
			return Rejected('Could not resolve the destination parent: ${Std.string(error)}');
		}

		final packageContentRoot = findPackageContentRoot(packageRoot);
		if (packageContentRoot == null) {
			return
				Rejected("The installed reflaxe.ocaml package does not contain scaffold templates. Reinstall the package or use a complete source checkout.");
		}
		if (isSameOrInside(packageContentRoot, targetRoot)) {
			return Rejected("Refusing to create a project inside the installed reflaxe.ocaml package.");
		}

		final selectedName = projectName == null ? Path.withoutDirectory(targetRoot) : projectName.trim();
		final nameError = validateProjectName(selectedName);
		if (nameError != null) {
			return Rejected(nameError);
		}
		final slug = projectSlug(selectedName);
		final variables = ["{{PROJECT_NAME}}" => selectedName, "{{PROJECT_SLUG}}" => slug];

		final templateRoot = Path.join([packageContentRoot, "templates", "scaffold", normalizedKind]);
		final templateFiles = try {
			collectTemplateFiles(templateRoot);
		} catch (error:Dynamic) {
			return Rejected('Could not read the $normalizedKind scaffold template: ${Std.string(error)}');
		}
		if (templateFiles == null || templateFiles.length == 0) {
			return Rejected('Scaffold template is missing or empty for kind "$normalizedKind". Reinstall reflaxe.ocaml.');
		}
		final rendered = new Array<ScaffoldTemplateFile>();
		for (template in templateFiles) {
			var contents = template.contents;
			for (marker => value in variables) {
				contents = contents.replace(marker, value);
			}
			if (~/\{\{[A-Z0-9_]+\}\}/.match(contents)) {
				return Rejected('Scaffold template contains an unknown placeholder in ${template.relativePath}.');
			}
			rendered.push({relativePath: template.relativePath, contents: contents});
		}

		final stagingRoot = targetRoot + STAGING_SUFFIX;
		if (FileSystem.exists(stagingRoot)) {
			return Rejected('A stale scaffold transaction already exists: $stagingRoot. Remove it after checking its contents, then retry.');
		}
		try {
			FileSystem.createDirectory(stagingRoot);
			for (template in rendered) {
				final outputPath = Path.join([stagingRoot, template.relativePath]);
				ensureDirectory(Path.directory(outputPath));
				File.saveContent(outputPath, template.contents);
			}
			FileSystem.rename(stagingRoot, targetRoot);
		} catch (error:Dynamic) {
			try {
				deleteTree(stagingRoot);
			} catch (_:Dynamic) {}
			return Rejected('Could not create scaffold: ${Std.string(error)}');
		}

		return Created({
			kind: normalizedKind,
			projectName: selectedName,
			destination: targetRoot,
			files: rendered.map(template -> template.relativePath)
		});
	}

	static function unsupportedKindMessage(kind:String):Null<String> {
		return switch (kind) {
			case "binding":
				"Binding scaffolds are not available yet because typed .mli import manifests are not implemented. No files were created.";
			case "adapter":
				"Adapter scaffolds are not available yet because native source and dependency ownership is not modeled. No files were created.";
			case "plugin" | "target":
				"Native plugin and target scaffolds are not available yet; they remain owned by the shared stock-Haxe/hxhx plugin SDK. No files were created.";
			case _:
				null;
		};
	}

	static function findPackageContentRoot(packageRoot:String):Null<String> {
		final candidates = [packageRoot, Path.join([packageRoot, "packages", "reflaxe.ocaml"])];
		for (candidate in candidates) {
			final templateRoot = Path.join([candidate, "templates", "scaffold"]);
			if (FileSystem.exists(templateRoot) && FileSystem.isDirectory(templateRoot)) {
				return FileSystem.fullPath(candidate);
			}
		}
		return null;
	}

	static function collectTemplateFiles(root:String):Null<Array<ScaffoldTemplateFile>> {
		if (!FileSystem.exists(root) || !FileSystem.isDirectory(root)) {
			return null;
		}
		final files = new Array<ScaffoldTemplateFile>();
		collectTemplateDirectory(root, root, files);
		files.sort((left, right) -> compareStrings(left.relativePath, right.relativePath));
		return files;
	}

	static function collectTemplateDirectory(root:String, directory:String, files:Array<ScaffoldTemplateFile>):Void {
		final entries = FileSystem.readDirectory(directory);
		entries.sort(compareStrings);
		for (entry in entries) {
			final absolute = Path.join([directory, entry]);
			if (FileSystem.isDirectory(absolute)) {
				collectTemplateDirectory(root, absolute, files);
			} else {
				final relative = slashPath(absolute.substr(Path.addTrailingSlash(root).length));
				files.push({relativePath: relative, contents: File.getContent(absolute)});
			}
		}
	}

	static function validateProjectName(value:String):Null<String> {
		if (value.length == 0 || value.length > 80) {
			return "Project names must contain between 1 and 80 characters.";
		}
		if (!~/^[A-Za-z][A-Za-z0-9._ -]*$/.match(value)) {
			return "Project names must start with a letter and contain only letters, digits, spaces, dots, underscores, or hyphens.";
		}
		return null;
	}

	static function projectSlug(value:String):String {
		final result = new StringBuf();
		var lastWasDash = false;
		for (index in 0...value.length) {
			final code = value.charCodeAt(index) ?? -1;
			final alphaNumeric = (code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
			if (alphaNumeric) {
				result.add(value.charAt(index).toLowerCase());
				lastWasDash = false;
			} else if (!lastWasDash) {
				result.add("-");
				lastWasDash = true;
			}
		}
		var slug = result.toString();
		while (slug.endsWith("-")) {
			slug = slug.substr(0, slug.length - 1);
		}
		return slug;
	}

	static function ensureDirectory(path:String):Void {
		if (path.length == 0 || FileSystem.exists(path)) {
			return;
		}
		ensureDirectory(Path.directory(path));
		FileSystem.createDirectory(path);
	}

	static function deleteTree(path:String):Void {
		if (!FileSystem.exists(path)) {
			return;
		}
		if (!FileSystem.isDirectory(path)) {
			FileSystem.deleteFile(path);
			return;
		}
		for (entry in FileSystem.readDirectory(path)) {
			deleteTree(Path.join([path, entry]));
		}
		FileSystem.deleteDirectory(path);
	}

	static function absoluteFrom(base:String, path:String):String {
		return Path.normalize(FileSystem.absolutePath(Path.isAbsolute(path) ? path : Path.join([base, path])));
	}

	static function isSameOrInside(parent:String, child:String):Bool {
		var normalizedParent = slashPath(Path.removeTrailingSlashes(FileSystem.absolutePath(parent)));
		var normalizedChild = slashPath(Path.removeTrailingSlashes(FileSystem.absolutePath(child)));
		if (Sys.systemName() == "Windows") {
			normalizedParent = normalizedParent.toLowerCase();
			normalizedChild = normalizedChild.toLowerCase();
		}
		return normalizedChild == normalizedParent || normalizedChild.startsWith(normalizedParent + "/");
	}

	static function slashPath(path:String):String {
		return path.replace("\\", "/");
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
