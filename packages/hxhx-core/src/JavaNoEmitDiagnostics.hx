import haxe.io.Path;

private typedef JavaNoEmitMethodInfo = {
	final name:String;
	final signature:String;
	final line:Int;
	final column:Int;
	final endColumn:Int;
};

private typedef JavaNoEmitClassInfo = {
	final name:String;
	final kind:String;
	final isAbstract:Bool;
	final extendsName:String;
	final implementsName:String;
	final line:Int;
	final column:Int;
	final endColumn:Int;
	final requirements:Array<JavaNoEmitMethodInfo>;
	final implementations:Array<String>;
};

private typedef JavaNoEmitOverloadInfo = {
	final name:String;
	final rawSig:String;
	final erasedSig:String;
	final line:Int;
	final column:Int;
	final endColumn:Int;
};

private typedef JavaNoEmitOverloadCollision = {
	final relation:String;
	final primary:JavaNoEmitOverloadInfo;
	final secondary:JavaNoEmitOverloadInfo;
};

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

	/**
		Return the first missing overloaded abstract-method implementation diagnostic.

		Target mapping:
		- Java rejects concrete classes that extend abstract classes without implementing
		  every overload whose erased JVM method surface must be concrete.
		- Stage3 no-emit currently stops before Java codegen, so this source-level validator
		  preserves the compile-fail contract until richer class/interface typing owns it.
	**/
	public static function abstractOverloadImplementationDiagnostic(typedModules:Array<TypedModule>):Null<String> {
		if (typedModules == null)
			return null;
		for (typed in typedModules) {
			if (typed == null)
				continue;
			final parsed = typed.getParsed();
			final diagnostic = abstractOverloadImplementationDiagnosticForParsed(parsed);
			if (diagnostic != null)
				return diagnostic;
		}
		return null;
	}

	/**
		Return Java overload-erasure diagnostics for no-output compile-fail runs.

		Target mapping:
		- Haxe overloads can differ only by function type hints, while Java erases Haxe
		  function-typed values to one target surface.
		- Stage3 no-emit validates that mismatch before emit so upstream Java compile-fail
		  workloads still see the target-specific Haxe diagnostic.
	**/
	public static function overloadCollisionDiagnostic(typedModules:Array<TypedModule>):Null<String> {
		if (typedModules == null)
			return null;
		for (typed in typedModules) {
			if (typed == null)
				continue;
			final parsed = typed.getParsed();
			final diagnostic = overloadCollisionDiagnosticForParsed(parsed);
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

	static function abstractOverloadImplementationDiagnosticForParsed(parsed:ParsedModule):Null<String> {
		if (parsed == null)
			return null;
		final source = parsed.getSource();
		if (source == null || source.length == 0 || source.indexOf("@:overload") < 0)
			return null;
		final classes = scanJavaNoEmitClasses(source);
		if (classes.length == 0)
			return null;
		final byName = new Map<String, JavaNoEmitClassInfo>();
		for (cls in classes)
			byName.set(cls.name, cls);
		for (cls in classes) {
			if (cls.kind != "class" || cls.isAbstract || cls.extendsName.length == 0)
				continue;
			final directSuper = byName.get(cls.extendsName);
			if (directSuper == null || !isAbstractClassChain(directSuper, byName))
				continue;
			final requirements = inheritedRequirements(directSuper, byName);
			if (requirements.length == 0)
				continue;
			final implemented = inheritedImplementations(cls, byName);
			final missing = new Array<JavaNoEmitMethodInfo>();
			for (req in requirements) {
				if (!implemented.exists(req.signature))
					missing.push(req);
			}
			if (missing.length > 0)
				return renderMissingAbstractOverloads(parsed.getFilePath(), cls, cls.extendsName, missing);
		}
		return null;
	}

	static function overloadCollisionDiagnosticForParsed(parsed:ParsedModule):Null<String> {
		if (parsed == null)
			return null;
		final source = parsed.getSource();
		if (source == null || source.length == 0 || source.indexOf("@:overload") < 0)
			return null;
		final sourceLines = source.split("\n");
		final collisions = new Array<JavaNoEmitOverloadCollision>();
		for (cls in HxModuleDecl.getClasses(parsed.getDecl())) {
			final seen = new Map<String, JavaNoEmitOverloadInfo>();
			final byName = new Map<String, Array<JavaNoEmitOverloadInfo>>();
			for (fn in HxClassDecl.getFunctions(cls)) {
				final meta = HxFunctionDecl.getMetadata(fn);
				if (!hasOverloadMetadata(meta))
					continue;
				final info = javaNoEmitOverloadInfo(fn, sourceLines);
				final key = info.name + "#" + info.erasedSig;
				final previous = seen.get(key);
				if (previous != null) {
					final relation = previous.rawSig == info.rawSig ? "same" : "similar";
					final sameNameSeen = byName.get(info.name);
					if (relation == "same" && sameNameSeen != null && hasEarlierDifferentRawSignature(sameNameSeen, previous.rawSig)) {
						collisions.push({
							relation: relation,
							primary: info,
							secondary: previous
						});
					} else {
						collisions.push({
							relation: relation,
							primary: previous,
							secondary: info
						});
					}
				} else {
					seen.set(key, info);
				}
				final named = byName.get(info.name);
				if (named == null)
					byName.set(info.name, [info]);
				else
					named.push(info);
			}
		}
		if (collisions.length == 0)
			return null;
		return renderOverloadCollisions(parsed.getFilePath(), collisions);
	}

	static function javaNoEmitOverloadInfo(fn:HxFunctionDecl, sourceLines:Array<String>):JavaNoEmitOverloadInfo {
		final pos = HxFunctionDecl.getPos(fn);
		final line = pos == null ? 0 : pos.getLine();
		final rawLine = line > 0 && line <= sourceLines.length ? stripTrailingCarriage(sourceLines[line - 1]) : "";
		return {
			name: HxFunctionDecl.getName(fn),
			rawSig: javaRawOverloadSignature(fn),
			erasedSig: javaErasedOverloadSignature(fn),
			line: line,
			column: overloadDeclarationColumn(rawLine, pos),
			endColumn: rawLine.length + 1
		};
	}

	static function hasOverloadMetadata(meta:Array<String>):Bool {
		if (meta == null)
			return false;
		for (item in meta) {
			if (item == "overload" || item == "@:overload")
				return true;
		}
		return false;
	}

	static function overloadDeclarationColumn(rawLine:String, pos:HxPos):Int {
		final staticIndex = rawLine.indexOf("static");
		if (staticIndex >= 0)
			return staticIndex + 1;
		final functionIndex = rawLine.indexOf("function");
		if (functionIndex >= 0)
			return functionIndex + 1;
		return pos == null ? 0 : pos.getColumn();
	}

	static function javaRawOverloadSignature(fn:HxFunctionDecl):String {
		final parts = new Array<String>();
		for (arg in HxFunctionDecl.getArgs(fn))
			parts.push(StringTools.trim(HxFunctionArg.getTypeHint(arg)));
		return parts.join(",");
	}

	static function javaErasedOverloadSignature(fn:HxFunctionDecl):String {
		final parts = new Array<String>();
		for (arg in HxFunctionDecl.getArgs(fn))
			parts.push(javaErasedOverloadArg(StringTools.trim(HxFunctionArg.getTypeHint(arg))));
		return parts.join(",");
	}

	static function javaErasedOverloadArg(typeHint:String):String {
		final compact = StringTools.replace(typeHint == null ? "" : typeHint, " ", "");
		if (compact.indexOf("->") >= 0)
			return "Function";
		if (compact.length == 0)
			return "Object";
		return compact;
	}

	static function hasEarlierDifferentRawSignature(seen:Array<JavaNoEmitOverloadInfo>, rawSig:String):Bool {
		for (info in seen) {
			if (info.rawSig != rawSig)
				return true;
		}
		return false;
	}

	static function renderOverloadCollisions(filePath:String, collisions:Array<JavaNoEmitOverloadCollision>):String {
		final file = diagnosticFileName(filePath);
		final lines = new Array<String>();
		for (collision in collisions) {
			final primary = collision.primary;
			lines.push(renderOverloadSpan(file, primary) + " : Another overloaded field of " + collision.relation + " signature was already declared : "
				+ primary.name);
			if (collision.relation == "similar")
				lines.push(renderOverloadSpan(file, primary) + " : ... The signatures are different in Haxe, but not in the target language");
			lines.push(renderOverloadSpan(file, collision.secondary) + " : ... The second field is declared here");
		}
		return lines.join("\n");
	}

	static function renderOverloadSpan(file:String, info:JavaNoEmitOverloadInfo):String {
		return file + ":" + Std.string(info.line) + ": characters " + Std.string(info.column) + "-" + Std.string(info.endColumn);
	}

	static function scanJavaNoEmitClasses(source:String):Array<JavaNoEmitClassInfo> {
		final classes = new Array<JavaNoEmitClassInfo>();
		final lines = source.split("\n");
		var current:Null<JavaNoEmitClassInfo> = null;
		var depth = 0;
		var pendingAbstractClass = false;
		var pendingAbstractMember = false;
		for (i in 0...lines.length) {
			final raw = stripTrailingCarriage(lines[i]);
			final trimmed = StringTools.trim(raw);
			if (trimmed.length == 0)
				continue;
			if (current == null) {
				if (trimmed == "abstract") {
					pendingAbstractClass = true;
					continue;
				}
				final parsed = parseJavaNoEmitClassLine(raw, i + 1, pendingAbstractClass);
				pendingAbstractClass = false;
				if (parsed != null) {
					classes.push(parsed);
					current = parsed;
					depth = braceDelta(raw);
					if (depth <= 0) {
						current = null;
						depth = 0;
					}
					continue;
				}
				continue;
			}

			if (trimmed == "abstract") {
				pendingAbstractMember = true;
			} else if (trimmed.indexOf("function ") >= 0) {
				final method = parseJavaNoEmitMethodLine(raw, i + 1);
				if (method != null) {
					final isRequirement = current.kind == "interface"
						|| (current.isAbstract && (pendingAbstractMember || StringTools.startsWith(trimmed, "abstract ")));
					if (isRequirement)
						current.requirements.push(method);
					else
						current.implementations.push(method.signature);
				}
				pendingAbstractMember = false;
			} else if (trimmed.indexOf("@:overload") < 0) {
				pendingAbstractMember = false;
			}

			depth += braceDelta(raw);
			if (depth <= 0) {
				current = null;
				depth = 0;
				pendingAbstractMember = false;
			}
		}
		return classes;
	}

	static function parseJavaNoEmitClassLine(raw:String, line:Int, pendingAbstract:Bool):Null<JavaNoEmitClassInfo> {
		final words = raw.split(" ");
		var sawAbstract = pendingAbstract;
		var kind = "";
		var name = "";
		var extendsName = "";
		var implementsName = "";
		var i = 0;
		while (i < words.length) {
			final word = cleanJavaNoEmitWord(words[i]);
			switch (word) {
				case "" | "@:keep" | "public" | "private":
				case "abstract":
					sawAbstract = true;
				case "interface":
					kind = "interface";
					if (i + 1 < words.length)
						name = cleanJavaNoEmitWord(words[i + 1]);
				case "class":
					kind = "class";
					if (i + 1 < words.length)
						name = cleanJavaNoEmitWord(words[i + 1]);
				case "extends":
					if (i + 1 < words.length)
						extendsName = cleanJavaNoEmitWord(words[i + 1]);
				case "implements":
					if (i + 1 < words.length)
						implementsName = cleanJavaNoEmitWord(words[i + 1]);
				case _:
			}
			i += 1;
		}
		if (kind.length == 0 || name.length == 0)
			return null;
		final column = raw.indexOf(name) + 1;
		return {
			name: name,
			kind: kind,
			isAbstract: sawAbstract,
			extendsName: extendsName,
			implementsName: implementsName,
			line: line,
			column: column,
			endColumn: column + name.length,
			requirements: [],
			implementations: []
		};
	}

	static function parseJavaNoEmitMethodLine(raw:String, line:Int):Null<JavaNoEmitMethodInfo> {
		final fnIndex = raw.indexOf("function ");
		if (fnIndex < 0)
			return null;
		final nameStart = fnIndex + "function ".length;
		final open = raw.indexOf("(", nameStart);
		final close = open < 0 ? -1 : raw.indexOf(")", open);
		if (open < 0 || close < 0)
			return null;
		final name = StringTools.trim(raw.substring(nameStart, open));
		if (name.length == 0)
			return null;
		final args = compactArgs(raw.substring(open + 1, close));
		final column = nameStart + 1;
		return {
			name: name,
			signature: name + "(" + args + ")",
			line: line,
			column: column,
			endColumn: column + name.length
		};
	}

	static function cleanJavaNoEmitWord(word:String):String {
		var out = StringTools.trim(word == null ? "" : word);
		while (out.length > 0) {
			final last = out.charAt(out.length - 1);
			if (last == "{" || last == "}" || last == "," || last == ";")
				out = out.substr(0, out.length - 1);
			else
				break;
		}
		return out;
	}

	static function compactArgs(args:String):String {
		final raw = StringTools.trim(args == null ? "" : args);
		if (raw.length == 0)
			return "";
		final parts = new Array<String>();
		for (part in raw.split(","))
			parts.push(StringTools.replace(StringTools.trim(part), " ", ""));
		return parts.join(",");
	}

	static function braceDelta(raw:String):Int {
		var delta = 0;
		for (i in 0...raw.length) {
			final ch = raw.charCodeAt(i);
			if (ch == "{".code)
				delta += 1;
			else if (ch == "}".code)
				delta -= 1;
		}
		return delta;
	}

	static function stripTrailingCarriage(line:String):String {
		if (line != null && line.length > 0 && line.charCodeAt(line.length - 1) == 13)
			return line.substr(0, line.length - 1);
		return line == null ? "" : line;
	}

	static function isAbstractClassChain(cls:JavaNoEmitClassInfo, byName:Map<String, JavaNoEmitClassInfo>):Bool {
		var current:Null<JavaNoEmitClassInfo> = cls;
		while (current != null) {
			if (current.isAbstract)
				return true;
			current = current.extendsName.length == 0 ? null : byName.get(current.extendsName);
		}
		return false;
	}

	static function inheritedRequirements(cls:JavaNoEmitClassInfo, byName:Map<String, JavaNoEmitClassInfo>):Array<JavaNoEmitMethodInfo> {
		final out = new Array<JavaNoEmitMethodInfo>();
		appendInheritedRequirements(out, cls, byName);
		return out;
	}

	static function appendInheritedRequirements(out:Array<JavaNoEmitMethodInfo>, cls:JavaNoEmitClassInfo, byName:Map<String, JavaNoEmitClassInfo>):Void {
		if (cls.extendsName.length > 0) {
			final parent = byName.get(cls.extendsName);
			if (parent != null)
				appendInheritedRequirements(out, parent, byName);
		}
		if (cls.implementsName.length > 0) {
			final iface = byName.get(cls.implementsName);
			if (iface != null)
				appendUniqueRequirements(out, iface.requirements);
		}
		appendUniqueRequirements(out, cls.requirements);
	}

	static function appendUniqueRequirements(out:Array<JavaNoEmitMethodInfo>, requirements:Array<JavaNoEmitMethodInfo>):Void {
		for (req in requirements) {
			var seen = false;
			for (existing in out) {
				if (existing.signature == req.signature) {
					seen = true;
					break;
				}
			}
			if (!seen)
				out.push(req);
		}
	}

	static function inheritedImplementations(cls:JavaNoEmitClassInfo, byName:Map<String, JavaNoEmitClassInfo>):Map<String, Bool> {
		final out = new Map<String, Bool>();
		appendInheritedImplementations(out, cls, byName);
		return out;
	}

	static function appendInheritedImplementations(out:Map<String, Bool>, cls:JavaNoEmitClassInfo, byName:Map<String, JavaNoEmitClassInfo>):Void {
		if (cls.extendsName.length > 0) {
			final parent = byName.get(cls.extendsName);
			if (parent != null)
				appendInheritedImplementations(out, parent, byName);
		}
		for (signature in cls.implementations)
			out.set(signature, true);
	}

	static function renderMissingAbstractOverloads(filePath:String, cls:JavaNoEmitClassInfo, superName:String, missing:Array<JavaNoEmitMethodInfo>):String {
		final file = diagnosticFileName(filePath);
		final plural = missing.length == 1 ? "method" : "methods";
		final pronoun = missing.length == 1 ? "it" : "them";
		final lines = [file + ":" + Std.string(cls.line) + ": characters " + Std.string(cls.column) + "-" + Std.string(cls.endColumn)
			+ " : This class extends abstract class " + superName + " but doesn't implement the following " + plural,
			file
			+ ":"
			+ Std.string(cls.line)
			+ ": characters "
			+ Std.string(cls.column)
			+ "-"
			+ Std.string(cls.endColumn)
			+ " : Implement "
			+ pronoun
			+ " or make "
			+ cls.name
			+ " abstract as well"];
		for (req in missing) {
			lines.push(file + ":" + Std.string(req.line) + ": characters " + Std.string(req.column) + "-" + Std.string(req.endColumn) + " : ... "
				+ req.signature);
		}
		return lines.join("\n");
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
