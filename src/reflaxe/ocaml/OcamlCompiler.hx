package reflaxe.ocaml;

#if (macro || reflaxe_runtime)

import haxe.io.Path;
#if macro
import haxe.macro.Context;
#end
import haxe.macro.Type;
import haxe.macro.Type.TConstant;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;

import reflaxe.DirectToStringCompiler;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import reflaxe.data.EnumOptionData;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlBuilder;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlModuleItem;
import reflaxe.ocaml.ast.OcamlLetBinding;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlPat;
import reflaxe.ocaml.ast.OcamlRecordField;
import reflaxe.ocaml.ast.OcamlTypeDecl;
import reflaxe.ocaml.ast.OcamlTypeDeclKind;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.ast.OcamlTypeRecordField;
import reflaxe.ocaml.ast.OcamlVariantConstructor;
import reflaxe.ocaml.runtimegen.DuneProjectEmitter;
import reflaxe.ocaml.runtimegen.OcamlBuildRunner;
import reflaxe.ocaml.runtimegen.OcamlNativeFunctorEmitter;
import reflaxe.ocaml.runtimegen.PackageAliasEmitter;
import reflaxe.ocaml.runtimegen.RuntimeCopier;
import reflaxe.GenericCompiler;
import reflaxe.output.DataAndFileInfo;
import reflaxe.ocaml.OcamlNameTools;

using StringTools;
using reflaxe.helpers.BaseTypeHelper;

/**
 * Minimal OCaml compiler scaffold.
 *
 * Milestone 0 goal: register with Reflaxe and emit at least one `.ml` file.
 * Later milestones replace string stubs with a real OCaml IR pipeline.
 */
class OcamlCompiler extends DirectToStringCompiler {
	public static var instance:OcamlCompiler;
	final ctx:CompilationContext = new CompilationContext();
	final printer:OcamlASTPrinter = new OcamlASTPrinter();
	var mainModuleId:Null<String> = null;
	var checkedOutputCollisions:Bool = false;

	#if macro
	static var haxeStdRoots:Null<Array<String>> = null;

	static function normalizePath(p:String):String {
		if (p == null) return "";
		var s = p.replace("\\", "/");
		if (!s.endsWith("/")) s += "/";
		return s;
	}

	static function detectHaxeStdRoots():Array<String> {
		if (haxeStdRoots != null) return haxeStdRoots;

		final roots:Array<String> = [];
		for (cp in haxe.macro.Context.getClassPath()) {
			if (cp == null || cp.length == 0) continue;

			// Identify the real Haxe std root by probing for known files.
			// Avoid confusing it with this repo's own `std/` folder.
			final stdHx = Path.join([cp, "Std.hx"]);
			final logHx = Path.join([cp, "haxe", "Log.hx"]);
			if (sys.FileSystem.exists(stdHx) && sys.FileSystem.exists(logHx)) {
				roots.push(normalizePath(cp));
			}
		}

		haxeStdRoots = roots;
		return roots;
	}

	static function isPosInHaxeStd(pos:haxe.macro.Expr.Position):Bool {
		final info = haxe.macro.Context.getPosInfos(pos);
		final file = normalizePath(info.file);
		for (root in detectHaxeStdRoots()) {
			if (StringTools.startsWith(file, root)) return true;
		}
		return false;
	}
	#end

	public function new() {
		super();
		instance = this;

		#if macro
		// Precompute inheritance participants after typing, before codegen starts.
		//
		// Why not compute lazily in `compileClassImpl`?
		// - Base classes can be compiled before derived classes.
		// - We need base classes to be marked “virtual” (method-field dispatch) before we emit them.
		Context.onAfterTyping(function(types:Array<haxe.macro.Type.ModuleType>) {
			if (ctx.virtualTypesComputed) return;
			ctx.virtualTypesComputed = true;

			// Primary-type mapping (naming): keep historical short names stable when a module
			// only contains a single type, even if that type name differs from the file/module name.
			final moduleToClasses:Map<String, Array<ClassType>> = [];

			inline function fullNameOf(c:ClassType):String {
				return (c.pack ?? []).concat([c.name]).join(".");
			}

			function markChain(c:ClassType):Void {
				var cur:Null<ClassType> = c;
				var guard = 0;
				while (cur != null && guard++ < 64) {
					ctx.virtualTypes.set(fullNameOf(cur), true);
					ctx.dispatchTypes.set(fullNameOf(cur), true);
					cur = cur.superClass != null ? cur.superClass.t.get() : null;
				}
			}

			for (t in types) {
				switch (t) {
					case TClassDecl(cRef):
						final c = cRef.get();

						if (!moduleToClasses.exists(c.module)) moduleToClasses.set(c.module, []);
						final list = moduleToClasses.get(c.module);
						if (list != null) list.push(c);

						if (c.isInterface) {
							ctx.interfaceTypes.set(fullNameOf(c), true);
						}
						if (c.interfaces != null && c.interfaces.length > 0 && !c.isInterface) {
							ctx.dispatchTypes.set(fullNameOf(c), true);
						}
						if (c.superClass != null) {
							markChain(c);
						}
					case _:
				}
			}

				for (moduleId => list in moduleToClasses) {
					if (list == null || list.length == 0) continue;
					final base = OcamlNameTools.moduleBaseName(moduleId);
					var primary:Null<String> = null;
				for (c in list) {
					if (c.name == base) {
						primary = c.name;
						break;
					}
				}
				if (primary == null) primary = list[0].name;
					if (primary != null) ctx.primaryTypeNameByModule.set(moduleId, primary);
				}

				// Mutable static field inference (M6+/bd: haxe.ocaml-xgv.3.7).
				//
				// Why
				// - OCaml `let` bindings are immutable, but Haxe `static var` fields can be reassigned.
				// - We need to know which static fields are written anywhere in the program so we can:
				//   - emit them as `ref` cells (`let x = ref <init>`)
				//   - lower reads/writes to `!x` and `x := v`.
				//
				// This is a whole-program decision: `MyClass.x = 1` may appear in a different module
				// than `MyClass` itself.
				ctx.mutableStaticFields.clear();

				inline function staticKey(c:ClassType, fieldName:String):String {
					return (c.pack ?? []).concat([c.name, fieldName]).join(".");
				}

				function markStaticLValue(lhs:TypedExpr):Void {
					switch (lhs.expr) {
						case TField(_, FStatic(cRef, cfRef)):
							final c = cRef.get();
							final cf = cfRef.get();
							switch (cf.kind) {
								case FVar(_, _):
									ctx.mutableStaticFields.set(staticKey(c, cf.name), true);
								case _:
							}
						case _:
					}
				}

				function scan(e:TypedExpr):Void {
					switch (e.expr) {
						case TBinop(OpAssign, lhs, _):
							markStaticLValue(lhs);
						case TBinop(OpAssignOp(_), lhs, _):
							markStaticLValue(lhs);
						case TUnop(OpIncrement, _, inner) | TUnop(OpDecrement, _, inner):
							markStaticLValue(inner);
						case _:
					}
					haxe.macro.TypedExprTools.iter(e, scan);
				}

				for (t in types) {
					switch (t) {
						case TClassDecl(cRef):
							final c = cRef.get();
							for (f in c.fields.get()) {
								final e = f.expr();
								if (e != null) scan(e);
							}
							for (f in c.statics.get()) {
								final e = f.expr();
								if (e != null) scan(e);
							}
						case _:
					}
				}
			});
			#end
		}

	public override function generateOutputIterator():Iterator<DataAndFileInfo<reflaxe.output.StringOrBytes>> {
		// Ensure type declarations (enums/typedefs/abstracts) appear before value
		// definitions in each module, since OCaml requires constructors/types to
		// be declared before use.
		//
		// Also ensure that for Haxe modules containing multiple types (e.g. `Main.hx` defines
		// both `Main` and `MyExn`), we emit non-primary types first. Otherwise the primary
		// type's compiled chunk can refer to helper values that appear later in the file,
		// which OCaml does not allow (no forward references for values).
		final sortedClasses:CompiledCollection<String> = {
			final withIndex:Array<{ item:DataAndFileInfo<String>, idx:Int }> = [];
			for (i in 0...classes.length) withIndex.push({ item: classes[i], idx: i });

			final moduleOrder:Map<String, Int> = [];
			var nextMod = 0;
			for (entry in withIndex) {
				final m = entry.item.baseType.module;
				if (!moduleOrder.exists(m)) moduleOrder.set(m, nextMod++);
			}

			inline function isPrimary(entry:{ item:DataAndFileInfo<String>, idx:Int }):Bool {
				final moduleId = entry.item.baseType.module;
				final primary = ctx.primaryTypeNameByModule.get(moduleId);
				if (primary != null) return entry.item.baseType.name == primary;
				return OcamlNameTools.isPrimaryTypeInModule(moduleId, entry.item.baseType.name);
			}

			withIndex.sort((a, b) -> {
				final modA = a.item.baseType.module;
				final modB = b.item.baseType.module;
				final ordA = moduleOrder.get(modA);
				final ordB = moduleOrder.get(modB);
				if (ordA != ordB) return ordA - ordB;

				final priA = isPrimary(a) ? 1 : 0;
				final priB = isPrimary(b) ? 1 : 0;
				if (priA != priB) return priA - priB;

				return a.idx - b.idx;
			});

			withIndex.map(e -> e.item);
		};

		final all:CompiledCollection<String> = enums.concat(typedefs).concat(abstracts).concat(sortedClasses);

		#if macro
		if (!checkedOutputCollisions) {
			checkedOutputCollisions = true;
			assertNoModuleNameCollisions(all);
		}
		#end

		// Improve OCaml error messages by ensuring the compiler reports locations using the
		// stable, user-facing file path in the output directory rather than dune's `_build/` paths.
		//
		// We do this by:
		// - grouping all type-chunks per output file here (instead of letting Reflaxe join them),
		// - then prefixing the combined module with an OCaml line directive:
		//     # 1 "MyModule.ml"
		//
		// This keeps line numbers stable and makes errors actionable without hunting
		// through dune artifacts. Disable with `-D ocaml_no_line_directives`.
		final useLineDirectives = #if macro !Context.defined("ocaml_no_line_directives") #else false #end;
		final ext = options.fileOutputExtension != null ? options.fileOutputExtension : "";

		final buckets:Map<String, { rep:DataAndFileInfo<String>, parts:Array<String> }> = [];
		final fileOrder:Array<String> = [];

		inline function outputKey(info:DataAndFileInfo<String>):String {
			final base = info.baseType.moduleId();
			return (info.overrideDirectory != null ? info.overrideDirectory + "/" : "") + (info.overrideFileName != null ? info.overrideFileName : base);
		}

		for (info in all) {
			final key = outputKey(info);
			if (!buckets.exists(key)) {
				buckets.set(key, { rep: info, parts: [] });
				fileOrder.push(key);
			}
			final b = buckets.get(key);
			if (b != null) b.parts.push(info.data);
		}

		var index = 0;
		return {
			hasNext: () -> index < fileOrder.length,
			next: () -> {
				final key = fileOrder[index++];
				final bucket = buckets.get(key);
				if (bucket == null) throw "Missing output bucket for: " + key;
				final joined = bucket.parts.join("\n\n");

				final out = if (!useLineDirectives || joined.length == 0) {
					joined;
				} else {
					final fileName = key + ext;
					"# 1 \"" + escapeOcamlString(fileName) + "\"\n" + joined;
				}

				return bucket.rep.withOutput(out);
			}
		};
	}

	#if macro
	static function isValidOcamlModuleName(name:String):Bool {
		if (name == null || name.length == 0) return false;
		final first = name.charCodeAt(0);
		final isUpper = first >= 65 && first <= 90;
		if (!isUpper) return false;
		for (i in 1...name.length) {
			final c = name.charCodeAt(i);
			final ok = (c >= 97 && c <= 122) // a-z
				|| (c >= 65 && c <= 90) // A-Z
				|| (c >= 48 && c <= 57) // 0-9
				|| c == 95; // _
			if (!ok) return false;
		}
		return true;
	}

	static function assertNoModuleNameCollisions(all:CompiledCollection<String>):Void {
		// Reflaxe writes output per module using `BaseTypeHelper.moduleId()` as the filename key.
		// That operation replaces '.' with '_' and keeps original case.
		//
		// We must detect collisions early because:
		// - `a.b.C` and `a_b.C` both become `a_b_C` (silent merge into one .ml file).
		// - `foo.Bar` and `Foo.Bar` become `foo_Bar` / `Foo_Bar`, which can collide on
		//   case-insensitive filesystems and/or map to the same OCaml module name.
		final fileKeyToModules:Map<String, Map<String, Bool>> = [];
		final fileKeyToFileIds:Map<String, Map<String, Bool>> = [];

		final ocamlNameToModules:Map<String, Map<String, Bool>> = [];
		final ocamlNameToFileIds:Map<String, Map<String, Bool>> = [];

		inline function addToSet(map:Map<String, Map<String, Bool>>, key:String, value:String):Void {
			if (!map.exists(key)) map.set(key, []);
			final s = map.get(key);
			if (s != null) s.set(value, true);
		}

		for (c in all) {
			final mod = c.baseType.module;
			final fileId = c.baseType.moduleId(); // '.' -> '_' (Reflaxe output key)

			final fileKey = fileId.toLowerCase();
			addToSet(fileKeyToModules, fileKey, mod);
			addToSet(fileKeyToFileIds, fileKey, fileId);

			final ocamlName = DuneProjectEmitter.ocamlModuleNameFromHaxeModuleId(fileId);
			addToSet(ocamlNameToModules, ocamlName, mod);
			addToSet(ocamlNameToFileIds, ocamlName, fileId);

			if (!isValidOcamlModuleName(ocamlName)) {
				Context.error(
					"reflaxe.ocaml (M8): invalid OCaml module name '" + ocamlName + "' derived from Haxe module '" + mod + "'.",
					Context.currentPos()
				);
			}
		}

		for (k => mods in fileKeyToModules) {
			if (mods == null) continue;
			var count = 0;
			final modList:Array<String> = [];
			for (m => _ in mods) {
				count += 1;
				modList.push(m);
			}
			if (count <= 1) continue;

			final fileIds = fileKeyToFileIds.get(k);
			final fileIdList:Array<String> = [];
			if (fileIds != null) for (f => _ in fileIds) fileIdList.push(f);
			modList.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
			fileIdList.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));

			Context.error(
				"reflaxe.ocaml (M8): module filename collision after flattening.\n"
				+ "The following Haxe modules would map to the same output file key '" + k + "':\n"
				+ "  - " + modList.join("\n  - ") + "\n"
				+ (fileIdList.length > 0 ? ("File ids involved: " + fileIdList.join(", ") + "\n") : "")
				+ "Rename one of the packages/modules to avoid '.'/'_' collisions.\n"
				+ "(bd: haxe.ocaml-28t.9.7)",
				Context.currentPos()
			);
		}

		for (ocamlName => mods in ocamlNameToModules) {
			if (mods == null) continue;
			var count = 0;
			final modList:Array<String> = [];
			for (m => _ in mods) {
				count += 1;
				modList.push(m);
			}
			if (count <= 1) continue;

			final fileIds = ocamlNameToFileIds.get(ocamlName);
			final fileIdList:Array<String> = [];
			if (fileIds != null) for (f => _ in fileIds) fileIdList.push(f);
			modList.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
			fileIdList.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));

			// This can happen even if the raw `fileId` differs only by case. OCaml's module name is
			// derived from the filename and starts uppercase, so two files can still define the same module.
			Context.error(
				"reflaxe.ocaml (M8): OCaml module name collision ('" + ocamlName + "').\n"
				+ "The following Haxe modules would define the same OCaml module:\n"
				+ "  - " + modList.join("\n  - ") + "\n"
				+ (fileIdList.length > 0 ? ("File ids involved: " + fileIdList.join(", ") + "\n") : "")
				+ "(bd: haxe.ocaml-28t.9.7)",
				Context.currentPos()
			);
		}
	}
	#end

	public function compileClassImpl(
		classType:ClassType,
		varFields:Array<ClassVarData>,
		funcFields:Array<ClassFuncData>
	):Null<String> {
		ctx.emittedHaxeModules.set(classType.module, true);
		ctx.currentModuleId = classType.module;
		ctx.currentTypeName = classType.name;
		ctx.variableRenameMap.clear();
		ctx.assignedVars.clear();
		#if macro
		ctx.currentIsHaxeStd = isPosInHaxeStd(classType.pos);
		#end

		final mainModule = getMainModule();
		final isMain = switch (mainModule) {
			case TClassDecl(clsRef):
				final m = clsRef.get();
				(m.module == classType.module) && (m.name == classType.name);
			case _: false;
		}
		if (isMain) {
			mainModuleId = StringTools.replace(classType.module, ".", "_");
		}

		final fullName = (classType.pack ?? []).concat([classType.name]).join(".");
		ctx.currentTypeFullName = fullName;
		ctx.classTagsByFullName.set(fullName, classTagsForClassType(classType));
		#if macro
		if (!ctx.currentIsHaxeStd) {
			ctx.nonStdTypeRegistryClasses.set(fullName, true);
		}
		#end
		if (classType.superClass != null) {
			final sup = classType.superClass.t.get();
			ctx.currentSuperFullName = (sup.pack ?? []).concat([sup.name]).join(".");
			ctx.currentSuperModuleId = sup.module;
			ctx.currentSuperTypeName = sup.name;
			ctx.currentSuperCtorArgs = null;
			if (sup.constructor != null) {
				final ctorField = sup.constructor.get();
				switch (TypeTools.follow(ctorField.type)) {
					case TFun(args, _):
						ctx.currentSuperCtorArgs = args;
					case _:
				}
			}
		} else {
			ctx.currentSuperFullName = null;
			ctx.currentSuperModuleId = null;
			ctx.currentSuperTypeName = null;
			ctx.currentSuperCtorArgs = null;
		}

			// Guardrails (M5+): fail fast for features we haven't implemented.
			#if macro
			if (!ctx.currentIsHaxeStd) {
				final problems:Array<String> = [];

				if (problems.length > 0) {
					haxe.macro.Context.error(
						"reflaxe.ocaml (M5): unsupported OO feature(s) in '" + fullName + "': " + problems.join("; ")
						+ ".\nSupported for now: single inheritance (`extends`) and interfaces (`implements`). (bd: haxe.ocaml-dwt.1.2)",
						classType.pos
					);
				}
			}
		#end

		final items:Array<OcamlModuleItem> = [];
		#if macro
		final sourceMapValue = haxe.macro.Context.definedValue("ocaml_sourcemap");
		final emitSourceMap = haxe.macro.Context.defined("ocaml_sourcemap")
			&& (sourceMapValue == null || sourceMapValue.length == 0 || sourceMapValue == "1" || sourceMapValue == "directives");
		#else
		final emitSourceMap = false;
		#end
		final builder = new OcamlBuilder(ctx, ocamlTypeExprFromHaxeType, emitSourceMap);

		// Header marker as a no-op binding to keep output non-empty and debuggable.
		items.push(OcamlModuleItem.ILet([{
			name: "__reflaxe_ocaml__",
			expr: OcamlExpr.EConst(OcamlConst.CUnit)
		}], false));

			final lets:Array<OcamlLetBinding> = [];

			// Instance surface (M5): record type + create + instance methods.
			final instanceVarsLocal = varFields.filter(v -> !v.isStatic);
			final hasInstanceVarsLocal = instanceVarsLocal.length > 0;

			// Default expressions are only available via `ClassVarData` for the class currently being compiled.
			// For inherited vars (declared in super classes), we fall back to `defaultValueForType`.
			final localVarInitByName:Map<String, TypedExpr> = [];
			for (v in instanceVarsLocal) {
				final init = v.findDefaultExpr();
				if (init != null) localVarInitByName.set(v.field.name, init);
			}

		var ctorFunc:Null<ClassFuncData> = null;
		final instanceMethods:Array<ClassFuncData> = [];
		for (f in funcFields) {
			if (f.expr == null) continue;
			if (f.isStatic) continue;
			if (f.field.name == "new") {
				ctorFunc = f;
			} else {
				instanceMethods.push(f);
			}
		}

				final hasInstanceSurface = hasInstanceVarsLocal || instanceMethods.length > 0 || ctorFunc != null;
			if (hasInstanceSurface) {
				final instanceTypeName = ctx.scopedInstanceTypeName(classType.module, classType.name);
				final createName = ctx.scopedValueName(classType.module, classType.name, "create");
				final ctorName = ctx.scopedValueName(classType.module, classType.name, "__ctor");

				final isDispatch = !classType.isInterface && ctx.dispatchTypes.exists(fullName);

					// For dynamic dispatch we need a list of all visible instance methods (including inherited)
					// so `obj.foo()` can be lowered to `obj.foo obj ...` regardless of where `foo` was declared.
					final dispatchMethodOrder:Array<String> = [];
					final dispatchMethodDecl:Map<String, { owner:ClassType, field:ClassField }> = [];
					var dispatchLayoutFields:Null<Array<{ name:String, kind:String, field:ClassField }>> = null;
					if (isDispatch) {
						function chainFromRoot(c:ClassType):Array<ClassType> {
							final chain:Array<ClassType> = [];
							var cur:Null<ClassType> = c;
							var guard = 0;
						while (cur != null && guard++ < 64) {
							chain.push(cur);
							cur = cur.superClass != null ? cur.superClass.t.get() : null;
						}
						chain.reverse();
						return chain;
					}

					function declaredInstanceMethodFields(c:ClassType):Array<ClassField> {
						final out:Array<ClassField> = [];
						for (cf in c.fields.get()) {
							if (cf == null) continue;
							if (cf.name == "new") continue;
							switch (cf.kind) {
								case FMethod(_):
									out.push(cf);
								case _:
							}
						}
						return out;
					}

					final chain = chainFromRoot(classType);
					final seen:Map<String, Bool> = [];
					for (c in chain) {
						for (cf in declaredInstanceMethodFields(c)) {
							if (seen.exists(cf.name)) continue;
							seen.set(cf.name, true);
							dispatchMethodOrder.push(cf.name);
						}
					}
						// Most-derived declaration wins (override).
						for (c in chain) {
							for (cf in declaredInstanceMethodFields(c)) {
								dispatchMethodDecl.set(cf.name, { owner: c, field: cf });
							}
						}

						// Record layout for dispatch instances: preserve a base-prefix layout across
						// the inheritance chain by emitting fields in per-level segments:
						//   (vars introduced at level0), (methods introduced at level0),
						//   (vars introduced at level1), (methods introduced at level1), ...
						//
						// This ensures that accessing inherited method fields through a base static type
						// works even when the runtime value is a subclass record.
						final layout:Array<{ name:String, kind:String, field:ClassField }> = [];
						final seenVars:Map<String, Bool> = [];
						final seenMethods2:Map<String, Bool> = [];

						for (c in chain) {
							for (cf in c.fields.get()) {
								if (cf == null) continue;
								switch (cf.kind) {
									case FVar(_, _):
										if (seenVars.exists(cf.name)) continue;
										seenVars.set(cf.name, true);
										layout.push({ name: cf.name, kind: "var", field: cf });
									case _:
								}
							}

							for (cf in declaredInstanceMethodFields(c)) {
								if (seenMethods2.exists(cf.name)) continue;
								seenMethods2.set(cf.name, true);
								layout.push({ name: cf.name, kind: "method", field: cf });
							}
						}

						dispatchLayoutFields = layout;
					}

				final isDispatchInstance = isDispatch && dispatchMethodOrder.length > 0;
				function exprMentionsIdent(e:OcamlExpr, target:String):Bool {
					function any(exprs:Array<OcamlExpr>):Bool {
						for (x in exprs) if (exprMentionsIdent(x, target)) return true;
						return false;
					}
					return switch (e) {
						case EPos(_, inner):
							exprMentionsIdent(inner, target);
						case EIdent(n):
							n == target;
						case EConst(_):
							false;
						case ERaw(_):
							false;
						case ERaise(exn):
							exprMentionsIdent(exn, target);
						case ELet(_, value, body, _):
							exprMentionsIdent(value, target) || exprMentionsIdent(body, target);
						case EFun(_, body):
							exprMentionsIdent(body, target);
						case EApp(fn, args):
							exprMentionsIdent(fn, target) || any(args);
						case EAppArgs(fn, args):
							exprMentionsIdent(fn, target) || any(args.map(a -> a.expr));
						case EBinop(_, left, right):
							exprMentionsIdent(left, target) || exprMentionsIdent(right, target);
						case EUnop(_, expr):
							exprMentionsIdent(expr, target);
						case EIf(cond, thenExpr, elseExpr):
							exprMentionsIdent(cond, target) || exprMentionsIdent(thenExpr, target) || exprMentionsIdent(elseExpr, target);
						case EMatch(scrutinee, cases):
							if (exprMentionsIdent(scrutinee, target)) {
								true;
							} else {
								var found = false;
								for (c in cases) {
									if (exprMentionsIdent(c.expr, target)) {
										found = true;
										break;
									}
									if (c.guard != null && exprMentionsIdent(c.guard, target)) {
										found = true;
										break;
									}
								}
								found;
							}
						case ETry(body, cases):
							if (exprMentionsIdent(body, target)) {
								true;
							} else {
								var found = false;
								for (c in cases) {
									if (exprMentionsIdent(c.expr, target)) {
										found = true;
										break;
									}
									if (c.guard != null && exprMentionsIdent(c.guard, target)) {
										found = true;
										break;
									}
								}
								found;
							}
						case ESeq(exprs):
							any(exprs);
						case EWhile(cond, body):
							exprMentionsIdent(cond, target) || exprMentionsIdent(body, target);
						case EList(items):
							any(items);
						case ERecord(fields):
							any(fields.map(f -> f.value));
						case EField(expr, _):
							exprMentionsIdent(expr, target);
						case EAssign(_, lhs, rhs):
							exprMentionsIdent(lhs, target) || exprMentionsIdent(rhs, target);
						case ETuple(items):
							any(items);
						case EAnnot(expr, _):
							exprMentionsIdent(expr, target);
					}
				}

				final typeFields:Array<OcamlTypeRecordField> = [];

				// Runtime class identity (M10): all class instances carry their most-derived class value
				// in the first record slot so `Type.getClass` can work even through `Obj.magic` upcasts.
					typeFields.push({
						name: "__hx_type",
						isMutable: false,
						typ: OcamlTypeExpr.TIdent("Obj.t")
					});
					if (isDispatchInstance && dispatchLayoutFields != null) {
						function buildDispatchMethodType(haxeMethodType:Type):OcamlTypeExpr {
							// Dispatch methods take `Obj.t` as the receiver so that interface + base-class
							// callsites can share a single representation without OCaml structural subtyping.
							final selfT = OcamlTypeExpr.TIdent("Obj.t");
						return switch (haxeMethodType) {
							case TFun(args, ret):
								var outT = ocamlTypeExprFromHaxeType(ret);
								if (args.length == 0) {
									// Calling convention: `foo()` always supplies `unit` at the callsite in OCaml.
									outT = OcamlTypeExpr.TArrow(OcamlTypeExpr.TIdent("unit"), outT);
								} else {
									for (i in 0...args.length) {
										final a = args[args.length - 1 - i];
										outT = OcamlTypeExpr.TArrow(ocamlTypeExprFromHaxeType(a.t), outT);
									}
								}
								OcamlTypeExpr.TArrow(selfT, outT);
							case _:
								// Should not happen for methods; fall back to a permissive type.
									OcamlTypeExpr.TIdent("Obj.t");
							}
						}
						for (entry in dispatchLayoutFields) {
							switch (entry.kind) {
								case "var":
									typeFields.push({
										name: entry.name,
										isMutable: true,
										typ: ocamlTypeExprFromHaxeType(entry.field.type)
									});
								case "method":
									final info = dispatchMethodDecl.get(entry.name);
									if (info == null) continue;
									typeFields.push({
										name: entry.name,
										isMutable: false,
										typ: buildDispatchMethodType(info.field.type)
									});
								case _:
							}
						}
					} else {
						if (hasInstanceVarsLocal) {
							for (v in instanceVarsLocal) {
								typeFields.push({
									name: v.field.name,
									isMutable: true,
									typ: ocamlTypeExprFromHaxeType(v.field.type)
								});
							}
						}
						if (isDispatchInstance) {
							function buildDispatchMethodType(haxeMethodType:Type):OcamlTypeExpr {
								// Dispatch methods take `Obj.t` as the receiver so that interface + base-class
								// callsites can share a single representation without OCaml structural subtyping.
								final selfT = OcamlTypeExpr.TIdent("Obj.t");
								return switch (haxeMethodType) {
									case TFun(args, ret):
										var outT = ocamlTypeExprFromHaxeType(ret);
										if (args.length == 0) {
											// Calling convention: `foo()` always supplies `unit` at the callsite in OCaml.
											outT = OcamlTypeExpr.TArrow(OcamlTypeExpr.TIdent("unit"), outT);
										} else {
											for (i in 0...args.length) {
												final a = args[args.length - 1 - i];
												outT = OcamlTypeExpr.TArrow(ocamlTypeExprFromHaxeType(a.t), outT);
											}
										}
										OcamlTypeExpr.TArrow(selfT, outT);
									case _:
										OcamlTypeExpr.TIdent("Obj.t");
								}
							}

							for (name in dispatchMethodOrder) {
								final info = dispatchMethodDecl.get(name);
								if (info == null) continue;
								typeFields.push({
									name: name,
									isMutable: false,
									typ: buildDispatchMethodType(info.field.type)
								});
							}
						}
					}

					final typeDecl:OcamlTypeDecl = {
						name: instanceTypeName,
						params: [],
						kind: OcamlTypeDeclKind.Record(typeFields)
					};
				items.push(OcamlModuleItem.IType([typeDecl], false));

				// create: allocate record, run ctor body, return self
				var createParams:Array<OcamlPat> = [OcamlPat.PConst(OcamlConst.CUnit)];
				var ctorBody:OcamlExpr = OcamlExpr.EConst(OcamlConst.CUnit);
				if (ctorFunc != null && ctorFunc.expr != null) {
				final argInfo = ctorFunc.args.map(a -> ({
					id: a.tvar != null ? a.tvar.id : -1,
					name: a.getName()
				}));
				switch (builder.buildFunctionFromArgsAndExpr(argInfo, ctorFunc.expr)) {
						case OcamlExpr.EFun(params, body):
							createParams = params;
							ctorBody = body;
						case _:
				}
			}

					final selfInit:OcamlExpr = if (hasInstanceVarsLocal || isDispatchInstance) {
						final fields:Array<OcamlRecordField> = [];
						fields.push({
							name: "__hx_type",
							value: OcamlExpr.EApp(
								OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "class_"),
								[OcamlExpr.EConst(OcamlConst.CString(fullName))]
							)
						});
						if (isDispatchInstance && dispatchLayoutFields != null) {
							function wrapperFor(owner:ClassType, methodType:Type, ownerBindingName:String):OcamlExpr {
								final ownerExpr = owner.module == classType.module
									? OcamlExpr.EIdent(ownerBindingName)
									: OcamlExpr.EField(OcamlExpr.EIdent(moduleIdToOcamlModuleName(owner.module)), ownerBindingName);

							final args:Null<Array<{ name:String, opt:Bool, t:Type }>> = switch (methodType) {
								case TFun(fargs, _): fargs;
								case _: null;
							}

							final params:Array<OcamlPat> = [OcamlPat.PVar("o")];
							final callArgs:Array<OcamlExpr> = [OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EIdent("o")])];

							if (args == null || args.length == 0) {
								// `foo()` call convention: include `unit`.
								params.push(OcamlPat.PConst(OcamlConst.CUnit));
								callArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
							} else {
								for (i in 0...args.length) {
									final n = "a" + Std.string(i);
									params.push(OcamlPat.PVar(n));
									callArgs.push(OcamlExpr.EIdent(n));
								}
							}

								return OcamlExpr.EFun(params, OcamlExpr.EApp(ownerExpr, callArgs));
							}

							for (entry in dispatchLayoutFields) {
								switch (entry.kind) {
									case "var":
										final init = localVarInitByName.exists(entry.name) ? localVarInitByName.get(entry.name) : null;
										final value = init != null ? builder.buildExpr(init) : defaultValueForType(entry.field.type);
										fields.push({ name: entry.name, value: value });
									case "method":
										final info = dispatchMethodDecl.get(entry.name);
										if (info == null) continue;
										final owner = info.owner;
										final ownerBinding = ctx.scopedValueName(owner.module, owner.name, entry.name + "__impl");
										final value = wrapperFor(owner, info.field.type, ownerBinding);
										fields.push({ name: entry.name, value: value });
									case _:
								}
							}
						} else {
							for (v in instanceVarsLocal) {
								final init = v.findDefaultExpr();
								final value = init != null ? builder.buildExpr(init) : defaultValueForType(v.field.type);
								fields.push({ name: v.field.name, value: value });
							}
							if (isDispatchInstance) {
								function wrapperFor(owner:ClassType, methodType:Type, ownerBindingName:String):OcamlExpr {
									final ownerExpr = owner.module == classType.module
										? OcamlExpr.EIdent(ownerBindingName)
										: OcamlExpr.EField(OcamlExpr.EIdent(moduleIdToOcamlModuleName(owner.module)), ownerBindingName);

									final args:Null<Array<{ name:String, opt:Bool, t:Type }>> = switch (methodType) {
										case TFun(fargs, _): fargs;
										case _: null;
									}

									final params:Array<OcamlPat> = [OcamlPat.PVar("o")];
									final callArgs:Array<OcamlExpr> = [OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EIdent("o")])];

									if (args == null || args.length == 0) {
										params.push(OcamlPat.PConst(OcamlConst.CUnit));
										callArgs.push(OcamlExpr.EConst(OcamlConst.CUnit));
									} else {
										for (i in 0...args.length) {
											final n = "a" + Std.string(i);
											params.push(OcamlPat.PVar(n));
											callArgs.push(OcamlExpr.EIdent(n));
										}
									}

									return OcamlExpr.EFun(params, OcamlExpr.EApp(ownerExpr, callArgs));
								}

								for (name in dispatchMethodOrder) {
									final info = dispatchMethodDecl.get(name);
									if (info == null) continue;
									final owner = info.owner;
									final ownerBinding = ctx.scopedValueName(owner.module, owner.name, name + "__impl");
									final value = wrapperFor(owner, info.field.type, ownerBinding);
									fields.push({ name: name, value: value });
								}
							}
						}
					 
						// Dune defaults can be warning-as-error; avoid `unused-var-strict` for `self`
						// by forcing a use when the body doesn't reference it.
					if (isDispatch && !exprMentionsIdent(ctorBody, "self")) {
						ctorBody = OcamlExpr.ESeq([OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [OcamlExpr.EIdent("self")]), ctorBody]);
					}
					final recordExpr = OcamlExpr.ERecord(fields);
					// Always annotate: `__hx_type` is a shared label across many records, and
					// some classes may otherwise become ambiguous for OCaml's record inference.
					OcamlExpr.EAnnot(recordExpr, OcamlTypeExpr.TIdent(instanceTypeName));
				} else {
					final recordExpr = OcamlExpr.ERecord([{
						name: "__hx_type",
						value: OcamlExpr.EApp(
							OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "class_"),
							[OcamlExpr.EConst(OcamlConst.CString(fullName))]
						)
					}]);
					OcamlExpr.EAnnot(recordExpr, OcamlTypeExpr.TIdent(instanceTypeName));
				}

				final createBody = OcamlExpr.ELet(
					"self",
					selfInit,
					OcamlExpr.ESeq([OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [ctorBody]), OcamlExpr.EIdent("self")]),
					false
				);
				lets.push({ name: createName, expr: OcamlExpr.EFun(createParams, createBody) });

				// Dispatch constructor function (used by `super()` lowering). This intentionally mirrors
				// the constructor body used in `create`, but takes `self` explicitly.
					if (isDispatch) {
						final selfPat = OcamlPat.PAnnot(OcamlPat.PVar("self"), OcamlTypeExpr.TIdent(instanceTypeName));
						final ctorBodyForCtor = !exprMentionsIdent(ctorBody, "self")
							? OcamlExpr.ESeq([OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [OcamlExpr.EIdent("self")]), ctorBody])
							: ctorBody;
						lets.push({
							name: ctorName,
							expr: OcamlExpr.EFun([selfPat].concat(createParams), OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [ctorBodyForCtor]))
						});
					}

			for (f in instanceMethods) {
				final compiled = {
					final argInfo = f.args.map(a -> ({
						id: a.tvar != null ? a.tvar.id : -1,
						name: a.getName()
					}));
							switch (builder.buildFunctionFromArgsAndExpr(argInfo, f.expr)) {
								case OcamlExpr.EFun(params, b):
									// Dune/OCaml flags can be warning-as-error; avoid `unused-var-strict` for `self`
									// by forcing a use when the method body doesn't reference it.
									final body = (!exprMentionsIdent(b, "self"))
										? OcamlExpr.ESeq([OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [OcamlExpr.EIdent("self")]), b])
										: b;
									final unitBody = funReturnsVoid(f.field.type)
										? OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [body])
										: body;
									OcamlExpr.EFun([OcamlPat.PVar("self")].concat(params), unitBody);
								case _:
									OcamlExpr.EFun([OcamlPat.PVar("self")], OcamlExpr.EConst(OcamlConst.CUnit));
							}
						};
					final methodName = isDispatch
						? ctx.scopedValueName(classType.module, classType.name, f.field.name + "__impl")
						: ctx.scopedValueName(classType.module, classType.name, f.field.name);
					final adjusted = if (isDispatch) {
						// Annotate `self` to avoid ambiguous record labels when multiple class records exist in a module.
						switch (compiled) {
							case OcamlExpr.EFun(params, body):
								final selfPat = OcamlPat.PAnnot(OcamlPat.PVar("self"), OcamlTypeExpr.TIdent(instanceTypeName));
							final rest = params.length > 0 ? params.slice(1) : [];
							OcamlExpr.EFun([selfPat].concat(rest), body);
						case _:
							compiled;
					}
				} else {
					compiled;
				}
				lets.push({ name: methodName, expr: adjusted });
			}
		}

		// Static functions (M2+)
		for (f in funcFields) {
			if (f.expr == null) continue;
			if (!f.isStatic) continue;

			final name = ctx.scopedValueName(classType.module, classType.name, f.field.name);
			final argInfo = f.args.map(a -> ({
				id: a.tvar != null ? a.tvar.id : -1,
				name: a.getName()
			}));
			final compiled = builder.buildFunctionFromArgsAndExpr(argInfo, f.expr);

			lets.push({ name: name, expr: compiled });
		}

		// Static vars (M6+)
		//
		// Haxe class-level `static var x = <expr>` becomes a module-level `let x = <expr>`.
		//
		// Note:
		// - This currently models *declaration + initialization* only.
		// - Reassignment semantics (`MyClass.x = v`) require an explicit representation decision
		//   (`ref` vs `mutable record field` vs other), and are handled separately.
			for (v in varFields) {
				if (!v.isStatic) continue;
				final name = ctx.scopedValueName(classType.module, classType.name, v.field.name);
				final key = (classType.pack ?? []).concat([classType.name, v.field.name]).join(".");
				final isMutableStatic = ctx.mutableStaticFields.exists(key) && ctx.mutableStaticFields.get(key) == true;
				// Static var initializers are stored on the field itself (not in the constructor pre-assignments
				// that `ClassVarData.findDefaultExpr()` uses for instance vars).
				final init = v.field.expr();
				final compiledInit = init != null ? builder.buildExpr(init) : defaultValueForType(v.field.type);
				final compiled = isMutableStatic ? OcamlExpr.EApp(OcamlExpr.EIdent("ref"), [compiledInit]) : compiledInit;
				lets.push({ name: name, expr: compiled });
			}
		if (lets.length > 0) {
			for (g in orderLetBindingsForOcaml(lets)) {
				items.push(OcamlModuleItem.ILet(g.bindings, g.isRec));
			}
		}

		var out = "(* Generated by reflaxe.ocaml (WIP) *)\n(* Haxe type: " + fullName + " *)\n\n";
		out += printer.printModule(items);

		return out;
	}

	public override function onOutputComplete() {
		#if eval
		if (output == null || output.outputDir == null) return;
		final outDir = output.outputDir;
		final useLineDirectives = #if macro !Context.defined("ocaml_no_line_directives") #else false #end;

		// Type registry (M10): allow `Type.resolveClass/resolveEnum` to work with runtime strings.
		//
		// We intentionally keep this conservative for now (non-stdlib only) to avoid bloating
		// small outputs. Expand once upstream suite running is in scope. (bd: haxe.ocaml-eli)
			{
				final classNames:Array<String> = [];
				for (k in ctx.nonStdTypeRegistryClasses.keys()) classNames.push(k);
				classNames.sort(Reflect.compare);

				final enumNames:Array<String> = [];
				for (k in ctx.nonStdTypeRegistryEnums.keys()) enumNames.push(k);
				enumNames.sort(Reflect.compare);

				// Typed catches (M10): runtime tag sets per compiled class, used to implement
				// `catch (e:T)` when the thrown value is typed as a supertype (or `Dynamic`).
				final classTagNames:Array<String> = [];
				for (k in ctx.classTagsByFullName.keys()) classTagNames.push(k);
				classTagNames.sort(Reflect.compare);

				function ocamlStringLiteral(s:String):String {
					return "\"" + escapeOcamlString(s) + "\"";
				}

				function ocamlStringListLiteral(items:Array<String>):String {
					if (items.length == 0) return "[]";
					return "[ " + items.map(ocamlStringLiteral).join("; ") + " ]";
				}

				final lines:Array<String> = [
					if (useLineDirectives) "# 1 \"HxTypeRegistry.ml\"" else null,
					"(* Generated by reflaxe.ocaml (WIP) *)",
					"(* Type registry used by `Type.resolveClass/resolveEnum` and typed catches. *)",
					"",
					"let init () : unit ="
				];
				lines.remove(null);

				if (classNames.length == 0 && enumNames.length == 0 && classTagNames.length == 0) {
					lines.push("  ()");
				} else {
					for (n in classNames) {
						lines.push("  ignore (HxType.class_ " + ocamlStringLiteral(n) + ");");
					}
					for (n in enumNames) {
						lines.push("  ignore (HxType.enum_ " + ocamlStringLiteral(n) + ");");
					}
					for (n in classTagNames) {
						final tags = ctx.classTagsByFullName.get(n);
						if (tags == null) continue;
						final sortedTags = tags.copy();
						sortedTags.sort(Reflect.compare);
						lines.push("  HxType.register_class_tags " + ocamlStringLiteral(n) + " " + ocamlStringListLiteral(sortedTags) + ";");
					}
					lines.push("  ()");
				}
				lines.push("");

				output.saveFile("HxTypeRegistry.ml", lines.join("\n"));
			}

		final noDune = haxe.macro.Context.defined("ocaml_no_dune");
		if (!noDune) {
			final duneLibsValue = haxe.macro.Context.definedValue("ocaml_dune_libraries");
			final duneLibs = duneLibsValue == null
				? ["unix", "str"]
				: duneLibsValue
					.split(",")
					.map(s -> StringTools.trim(s))
					.filter(s -> s.length > 0);

			final duneLayoutValue = haxe.macro.Context.definedValue("ocaml_dune_layout");

			final exesValue = haxe.macro.Context.definedValue("ocaml_dune_exes");
			final executables = if (exesValue == null || StringTools.trim(exesValue).length == 0) {
				null;
			} else {
				final out:Array<{ name:String, mainModuleId:Null<String> }> = [];
				for (entry in exesValue.split(",")) {
					final e = StringTools.trim(entry);
					if (e.length == 0) continue;
					final colon = e.indexOf(":");
					if (colon < 0) {
						// Name only; use the compilation main module if available.
						out.push({ name: e, mainModuleId: mainModuleId });
					} else {
						final exe = StringTools.trim(e.substr(0, colon));
						final mod = StringTools.trim(e.substr(colon + 1));
						if (exe.length == 0) continue;
						final modId = mod.length == 0 ? mainModuleId : StringTools.replace(mod, ".", "_");
						out.push({ name: exe, mainModuleId: modId });
					}
				}
				out.length > 0 ? out : null;
			}

			DuneProjectEmitter.emit(output, {
				projectName: DuneProjectEmitter.defaultProjectName(outDir),
				exeName: DuneProjectEmitter.defaultExeName(outDir),
				mainModuleId: mainModuleId,
				duneLibraries: duneLibs,
				duneLayout: duneLayoutValue,
				executables: executables
			});
		}

		final noRuntime = haxe.macro.Context.defined("ocaml_no_runtime");
		if (!noRuntime) {
			RuntimeCopier.copy(output, "runtime");
		}

		// OCaml-native (M12): emit functor-instantiated modules when requested by interop surfaces.
		if (ctx.needsOcamlNativeMapSet) {
			OcamlNativeFunctorEmitter.emitMapSet(output);
		}

		// Package alias modules (M8): generate dot-path access helpers unless disabled.
		final emitAliasesValue = haxe.macro.Context.definedValue("ocaml_emit_package_aliases");
		final emitAliases = emitAliasesValue == null || emitAliasesValue != "0";
		if (emitAliases) {
			final modules:Array<String> = [];
			for (m => _ in ctx.emittedHaxeModules) modules.push(m);
			PackageAliasEmitter.emit(output, modules);
		}

		final buildMode = haxe.macro.Context.definedValue("ocaml_build");
		final shouldRun = haxe.macro.Context.defined("ocaml_run");
		final noBuild = haxe.macro.Context.defined("ocaml_no_build");
		final emitOnly = haxe.macro.Context.defined("ocaml_emit_only");

		final mliValue = haxe.macro.Context.definedValue("ocaml_mli");
		final wantsMli = haxe.macro.Context.defined("ocaml_mli") || mliValue != null;
		final mliMode = if (!wantsMli) {
			null;
		} else if (mliValue == null || mliValue.length == 0 || mliValue == "1") {
			"infer";
		} else {
			mliValue;
		}
		final mliBestEffort = haxe.macro.Context.defined("ocaml_mli_best_effort");
		final mliStrict = wantsMli && !mliBestEffort;

		if (wantsMli && (noBuild || emitOnly)) {
			haxe.macro.Context.warning(
				"ocaml_mli implies a dune build/typecheck step; ignoring ocaml_no_build/ocaml_emit_only.",
				haxe.macro.Context.currentPos()
			);
		}
		if (wantsMli && noDune) {
			haxe.macro.Context.error(
				"ocaml_mli requires dune scaffolding (or a dune project in the output dir). Disable ocaml_no_dune.",
				haxe.macro.Context.currentPos()
			);
		}

		final shouldBuild = wantsMli || (!noBuild && !emitOnly);
		final strictBuild = buildMode != null;
		final strictAny = strictBuild || (wantsMli && mliStrict);

		if (!shouldBuild && !shouldRun && buildMode == null && !wantsMli) return;

		final exeName = DuneProjectEmitter.defaultExeName(outDir);
		final mode = buildMode != null ? buildMode : "native";

		final result = OcamlBuildRunner.tryBuildAndMaybeRun({
			outDir: outDir,
			exeName: exeName,
			mode: mode,
			run: shouldRun,
			strict: strictAny,
			mli: mliMode,
			mliStrict: mliStrict
		});

		switch (result) {
			case Ok(msg):
				if (msg != null) haxe.macro.Context.warning(msg, haxe.macro.Context.currentPos());
			case Err(msg):
				// Strict mode (ocaml_build=...) should stop compilation if build fails.
				haxe.macro.Context.error(msg, haxe.macro.Context.currentPos());
		}
		#end
	}

	public function compileEnumImpl(enumType:EnumType, options:Array<EnumOptionData>):Null<String> {
		ctx.emittedHaxeModules.set(enumType.module, true);
		ctx.currentModuleId = enumType.module;
		final fullName = (enumType.pack ?? []).concat([enumType.name]).join(".");
		#if macro
		ctx.currentIsHaxeStd = isPosInHaxeStd(enumType.pos);
		if (!ctx.currentIsHaxeStd) {
			ctx.nonStdTypeRegistryEnums.set(fullName, true);
		}
		#end

		// ocaml.* surface types map to native Stdlib types; do not emit duplicate type decls.
		if (enumType.pack != null && enumType.pack.length == 1 && enumType.pack[0] == "ocaml") {
			switch (enumType.name) {
				case "List", "Option", "Result":
					return null;
				case _:
			}
		}

		final typeName = ocamlTypeName(enumType.name);
		final typeParams = enumType.params.map(p -> ocamlTypeParam(p.name));

		final ctors:Array<OcamlVariantConstructor> = [];
		for (opt in options) {
			final args:Array<OcamlTypeExpr> = [];
			for (a in opt.args) {
				var argType = ocamlTypeExprFromHaxeType(a.type);
				if (a.opt) {
					// Haxe optional enum-constructor arguments (`?x:T`) behave like `Null<T>`.
					//
					// For most OCaml representations we can keep the underlying type and rely on
					// the `HxRuntime.hx_null` sentinel (cast via `Obj.magic`) at callsites.
					//
					// However, for primitives (Int/Float/Bool) we cannot safely represent a null
					// sentinel *as a primitive*, so we use the nullable-primitive representation:
					// `Obj.t` with `HxRuntime.hx_null` for null and `Obj.repr <prim>` for non-null.
					argType = switch (TypeTools.follow(a.type)) {
						case TAbstract(aRef, _):
							final abs = aRef.get();
							(abs.name == "Int" || abs.name == "Float" || abs.name == "Bool")
								? OcamlTypeExpr.TIdent("Obj.t")
								: argType;
						case _:
							argType;
					}
				}
				args.push(argType);
			}
			ctors.push({ name: opt.name, args: args });
		}

		final decl:OcamlTypeDecl = {
			name: typeName,
			params: typeParams,
			kind: OcamlTypeDeclKind.Variant(ctors)
		};

		final items:Array<OcamlModuleItem> = [OcamlModuleItem.IType([decl], false)];

		var out = "(* Generated by reflaxe.ocaml (WIP) *)\n(* Haxe enum: " + fullName + " *)\n\n";
		out += printer.printModule(items);
		return out;
	}

	public function compileExpressionImpl(expr:TypedExpr, topLevel:Bool):Null<String> {
		#if macro
		final sourceMapValue = haxe.macro.Context.definedValue("ocaml_sourcemap");
		final emitSourceMap = haxe.macro.Context.defined("ocaml_sourcemap")
			&& (sourceMapValue == null || sourceMapValue.length == 0 || sourceMapValue == "1" || sourceMapValue == "directives");
		#else
		final emitSourceMap = false;
		#end
		final builder = new OcamlBuilder(ctx, ocamlTypeExprFromHaxeType, emitSourceMap);
		final e = builder.buildExpr(expr);
		return printer.printExpr(e);
	}

	function compileConstant(c:TConstant):Null<String> {
		return switch (c) {
			case TInt(i): Std.string(i);
			case TFloat(f): Std.string(f);
			case TString(s): "\"" + escapeOcamlString(s) + "\"";
			case TBool(b): b ? "true" : "false";
			case TNull: "()"; // placeholder
			case TThis: "self"; // placeholder
			case TSuper: "super"; // placeholder
		}
	}

	static function escapeOcamlString(s:String):String {
		// Minimal escaping for scaffold output; printer milestone will replace.
		return s
			.replace("\\", "\\\\")
			.replace("\"", "\\\"")
			.replace("\n", "\\n")
			.replace("\r", "\\r")
			.replace("\t", "\\t");
	}

	static function ocamlTypeName(haxeName:String):String {
		if (haxeName == null || haxeName.length == 0) return "t";
		final first = haxeName.charCodeAt(0);
		final isUpper = first >= 65 && first <= 90;
		var s = (isUpper ? String.fromCharCode(first + 32) : haxeName.substr(0, 1)) + haxeName.substr(1);
		s = sanitizeLowerIdent(s);
		return s.length > 0 ? s : "t";
	}

	static function ocamlTypeParam(haxeName:String):String {
		if (haxeName == null || haxeName.length == 0) return "a";
		return sanitizeLowerIdent(haxeName.toLowerCase());
	}

	static function sanitizeLowerIdent(name:String):String {
		final out = new StringBuf();
		for (i in 0...name.length) {
			final c = name.charCodeAt(i);
			final isAlphaNum = (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57);
			out.add(isAlphaNum ? String.fromCharCode(c).toLowerCase() : "_");
		}
		var s = out.toString();
		if (s.length == 0) return s;
		final first = s.charCodeAt(0);
		if (first >= 48 && first <= 57) s = "_" + s;
		return s;
	}

	static function moduleIdToOcamlModuleName(moduleId:String):String {
		if (moduleId == null || moduleId.length == 0) return "Main";
		final flat = moduleId.split(".").join("_");
		return flat.substr(0, 1).toUpperCase() + flat.substr(1);
	}

	function ocamlTypeExprFromHaxeType(t:Type):OcamlTypeExpr {
		return switch (t) {
				case TAbstract(aRef, params):
					final a = aRef.get();
					final aPack = a.pack ?? [];

					// OCaml-native surface: treat `ocaml.*` abstracts as concrete OCaml types so they can
					// appear in generated type annotations (records, signatures, future .mli output)
					// without degrading to `Obj.t`.
					if (aPack.length == 1 && aPack[0] == "ocaml") {
						switch (a.name) {
							case "Array":
								final elem = (params != null && params.length > 0)
									? ocamlTypeExprFromHaxeType(params[0])
									: OcamlTypeExpr.TIdent("Obj.t");
								return OcamlTypeExpr.TApp("array", [elem]);
							case "StringMap":
								final v = (params != null && params.length > 0)
									? ocamlTypeExprFromHaxeType(params[0])
									: OcamlTypeExpr.TIdent("Obj.t");
								return OcamlTypeExpr.TApp("OcamlNativeStringMap.t", [v]);
							case "IntMap":
								final v = (params != null && params.length > 0)
									? ocamlTypeExprFromHaxeType(params[0])
									: OcamlTypeExpr.TIdent("Obj.t");
								return OcamlTypeExpr.TApp("OcamlNativeIntMap.t", [v]);
							case "StringSet":
								return OcamlTypeExpr.TIdent("OcamlNativeStringSet.t");
							case "IntSet":
								return OcamlTypeExpr.TIdent("OcamlNativeIntSet.t");
							case "Bytes":
								return OcamlTypeExpr.TIdent("bytes");
								case "Char":
									return OcamlTypeExpr.TIdent("char");
								case "Buffer":
									return OcamlTypeExpr.TIdent("Stdlib.Buffer.t");
								case "Hashtbl":
									final k = (params != null && params.length > 0)
										? ocamlTypeExprFromHaxeType(params[0])
										: OcamlTypeExpr.TIdent("Obj.t");
								final v = (params != null && params.length > 1)
									? ocamlTypeExprFromHaxeType(params[1])
									: OcamlTypeExpr.TIdent("Obj.t");
								return OcamlTypeExpr.TApp("Stdlib.Hashtbl.t", [k, v]);
							case "Seq":
								final elem = (params != null && params.length > 0)
									? ocamlTypeExprFromHaxeType(params[0])
									: OcamlTypeExpr.TIdent("Obj.t");
								return OcamlTypeExpr.TApp("Stdlib.Seq.t", [elem]);
							case _:
						}
					} else if (aPack.length == 2 && aPack[0] == "ocaml" && aPack[1] == "extlib" && a.name == "PMap") {
						final k = (params != null && params.length > 0)
							? ocamlTypeExprFromHaxeType(params[0])
							: OcamlTypeExpr.TIdent("Obj.t");
						final v = (params != null && params.length > 1)
							? ocamlTypeExprFromHaxeType(params[1])
							: OcamlTypeExpr.TIdent("Obj.t");
						return OcamlTypeExpr.TApp("PMap.t", [k, v]);
					}
					switch (a.name) {
						case "Int": OcamlTypeExpr.TIdent("int");
						case "Float": OcamlTypeExpr.TIdent("float");
						case "Bool": OcamlTypeExpr.TIdent("bool");
						case "Void": OcamlTypeExpr.TIdent("unit");
						case "CallStack":
							// `haxe.CallStack` is an abstract over `Array<haxe.StackItem>`.
							// For OCaml output, represent it as its underlying array type so functions like
							// `haxe.CallStack.toString` can accept it without `Obj.magic` gymnastics.
							ocamlTypeExprFromHaxeType(a.type);
						case "Null":
							// `Null<T>` uses the backend's nullable representation for `T`.
							//
							// - `Null<Int/Float/Bool>` => `Obj.t` (uses `HxRuntime.hx_null` sentinel).
							// - `Null<String>` => `string` (uses `Obj.magic HxRuntime.hx_null` sentinel).
						// - `Null<Enum>` => `Obj.t` (enums are variants; we avoid `Obj.magic` sentinels).
						// - `Null<Class>` => the underlying record type (uses `Obj.magic` sentinel).
							if (params != null && params.length == 1) {
								switch (TypeTools.follow(params[0])) {
									case TAbstract(innerRef, _):
										final inner = innerRef.get();
										(inner.name == "Int" || inner.name == "Float" || inner.name == "Bool")
											? OcamlTypeExpr.TIdent("Obj.t")
											: (inner.name == "CallStack" ? ocamlTypeExprFromHaxeType(innerRef.get().type) : OcamlTypeExpr.TIdent("Obj.t"));
									case TInst(cRef, innerParams):
										final c = cRef.get();
										switch (c.kind) {
											case KTypeParameter(_):
												// Portable mode doesn't model polymorphic class parameters in OCaml.
												// Treat them as an opaque runtime value type.
												return OcamlTypeExpr.TIdent("Obj.t");
											case _:
										}
										if (c.pack != null && c.pack.length == 0 && c.name == "String") {
											OcamlTypeExpr.TIdent("string");
										} else if (c.pack != null && c.pack.length == 0 && c.name == "Array") {
											final elem = innerParams.length > 0 ? ocamlTypeExprFromHaxeType(innerParams[0]) : OcamlTypeExpr.TIdent("Obj.t");
											OcamlTypeExpr.TApp("HxArray.t", [elem]);
										} else if (c.pack != null && c.pack.length == 2 && c.pack[0] == "haxe" && c.pack[1] == "ds" && c.name == "StringMap") {
											final v = innerParams.length > 0 ? ocamlTypeExprFromHaxeType(innerParams[0]) : OcamlTypeExpr.TIdent("Obj.t");
											OcamlTypeExpr.TApp("HxMap.string_map", [v]);
										} else if (c.pack != null && c.pack.length == 2 && c.pack[0] == "haxe" && c.pack[1] == "ds" && c.name == "IntMap") {
											final v = innerParams.length > 0 ? ocamlTypeExprFromHaxeType(innerParams[0]) : OcamlTypeExpr.TIdent("Obj.t");
											OcamlTypeExpr.TApp("HxMap.int_map", [v]);
										} else if (c.pack != null && c.pack.length == 2 && c.pack[0] == "haxe" && c.pack[1] == "ds" && c.name == "ObjectMap") {
											final k = innerParams.length > 0 ? ocamlTypeExprFromHaxeType(innerParams[0]) : OcamlTypeExpr.TIdent("Obj.t");
											final v = innerParams.length > 1 ? ocamlTypeExprFromHaxeType(innerParams[1]) : OcamlTypeExpr.TIdent("Obj.t");
											OcamlTypeExpr.TApp("HxMap.obj_map", [k, v]);
										} else if (c.pack != null && c.pack.length == 2 && c.pack[0] == "haxe" && c.pack[1] == "io" && c.name == "Bytes") {
											OcamlTypeExpr.TIdent("HxBytes.t");
										} else if (c.isExtern) {
											OcamlTypeExpr.TIdent("Obj.t");
										} else {
											final modName = moduleIdToOcamlModuleName(c.module);
											final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
											final scoped = ctx.scopedInstanceTypeName(c.module, c.name);
											final full = (selfMod != null && selfMod == modName) ? scoped : (modName + "." + scoped);
											OcamlTypeExpr.TIdent(full);
										}
									case TEnum(_, _):
										OcamlTypeExpr.TIdent("Obj.t");
									case _:
										OcamlTypeExpr.TIdent("Obj.t");
								}
						} else {
							OcamlTypeExpr.TIdent("Obj.t");
						}
					default: OcamlTypeExpr.TIdent("Obj.t");
				}
			case TInst(cRef, params):
				final c = cRef.get();
				switch (c.kind) {
					case KTypeParameter(_):
						// Portable mode doesn't model polymorphic class parameters in OCaml.
						// Treat them as an opaque runtime value type.
						return OcamlTypeExpr.TIdent("Obj.t");
					case _:
				}
				if (c.pack != null && c.pack.length == 0 && c.name == "String") {
					OcamlTypeExpr.TIdent("string");
				} else if (c.pack != null && c.pack.length == 0 && c.name == "Array") {
					// Haxe Array<T> -> 't HxArray.t (runtime is permissive; type is best-effort).
					final elem = params.length > 0 ? ocamlTypeExprFromHaxeType(params[0]) : OcamlTypeExpr.TIdent("Obj.t");
					OcamlTypeExpr.TApp("HxArray.t", [elem]);
				} else if (c.pack != null && c.pack.length == 2 && c.pack[0] == "haxe" && c.pack[1] == "ds" && c.name == "StringMap") {
					final v = params.length > 0 ? ocamlTypeExprFromHaxeType(params[0]) : OcamlTypeExpr.TIdent("Obj.t");
					OcamlTypeExpr.TApp("HxMap.string_map", [v]);
				} else if (c.pack != null && c.pack.length == 2 && c.pack[0] == "haxe" && c.pack[1] == "ds" && c.name == "IntMap") {
					final v = params.length > 0 ? ocamlTypeExprFromHaxeType(params[0]) : OcamlTypeExpr.TIdent("Obj.t");
					OcamlTypeExpr.TApp("HxMap.int_map", [v]);
				} else if (c.pack != null && c.pack.length == 2 && c.pack[0] == "haxe" && c.pack[1] == "ds" && c.name == "ObjectMap") {
					final k = params.length > 0 ? ocamlTypeExprFromHaxeType(params[0]) : OcamlTypeExpr.TIdent("Obj.t");
					final v = params.length > 1 ? ocamlTypeExprFromHaxeType(params[1]) : OcamlTypeExpr.TIdent("Obj.t");
					OcamlTypeExpr.TApp("HxMap.obj_map", [k, v]);
				} else if (c.pack != null && c.pack.length == 2 && c.pack[0] == "haxe" && c.pack[1] == "io" && c.name == "Bytes") {
					OcamlTypeExpr.TIdent("HxBytes.t");
				} else if (c.pack != null && c.pack.length == 1 && c.pack[0] == "ocaml" && c.name == "Ref") {
					final elem = params.length > 0 ? ocamlTypeExprFromHaxeType(params[0]) : OcamlTypeExpr.TIdent("Obj.t");
					OcamlTypeExpr.TApp("ref", [elem]);
				} else if (c.isExtern) {
					OcamlTypeExpr.TIdent("Obj.t");
				} else {
					// User class instances are represented by the module's `t` type.
					final modName = moduleIdToOcamlModuleName(c.module);
					final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
					final scoped = ctx.scopedInstanceTypeName(c.module, c.name);
					final full = (selfMod != null && selfMod == modName) ? scoped : (modName + "." + scoped);
					OcamlTypeExpr.TIdent(full);
				}
			case TEnum(eRef, params):
				final e = eRef.get();
				final ePack = e.pack ?? [];

				// OCaml-native surface: map `ocaml.List/Option/Result` types to Stdlib types.
				// (We still special-case constructors/patterns separately in the builder.)
				if (ePack.length == 1 && ePack[0] == "ocaml") {
					switch (e.name) {
						case "List":
							final elem = params.length > 0 ? ocamlTypeExprFromHaxeType(params[0]) : OcamlTypeExpr.TIdent("Obj.t");
							return OcamlTypeExpr.TApp("list", [elem]);
						case "Option":
							final elem = params.length > 0 ? ocamlTypeExprFromHaxeType(params[0]) : OcamlTypeExpr.TIdent("Obj.t");
							return OcamlTypeExpr.TApp("option", [elem]);
						case "Result":
							final okT = params.length > 0 ? ocamlTypeExprFromHaxeType(params[0]) : OcamlTypeExpr.TIdent("Obj.t");
							final errT = params.length > 1 ? ocamlTypeExprFromHaxeType(params[1]) : OcamlTypeExpr.TIdent("Obj.t");
							return OcamlTypeExpr.TApp("result", [okT, errT]);
						case _:
					}
				}
				final modName = moduleIdToOcamlModuleName(e.module);
				final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
				final typeName = ocamlTypeName(e.name);
				final full = (selfMod != null && selfMod == modName) ? typeName : (modName + "." + typeName);
				params.length == 0 ? OcamlTypeExpr.TIdent(full) : OcamlTypeExpr.TApp(full, params.map(ocamlTypeExprFromHaxeType));
			case TType(tRef, _):
				OcamlTypeExpr.TIdent("Obj.t");
			case TDynamic(_), TAnonymous(_), TMono(_), TLazy(_):
				OcamlTypeExpr.TIdent("Obj.t");
			case TFun(_, _):
				OcamlTypeExpr.TIdent("Obj.t");
		}
	}

	static inline function fullNameOfClassType(cls:ClassType):String {
		return (cls.pack ?? []).concat([cls.name]).join(".");
	}

	static function isVoidType(t:Type):Bool {
		return switch (TypeTools.follow(t)) {
			case TAbstract(aRef, _):
				final a = aRef.get();
				(a.pack ?? []).length == 0 && a.name == "Void";
			case _:
				false;
		}
	}

	static function funReturnsVoid(t:Type):Bool {
		return switch (t) {
			case TFun(_, ret): isVoidType(ret);
			case _: false;
		}
	}

	static function classTagsForClassType(cls:ClassType):Array<String> {
		final tags:Array<String> = [];
		final visited:Map<String, Bool> = [];

		inline function add(tag:String):Void {
			if (!visited.exists(tag)) {
				visited.set(tag, true);
				tags.push(tag);
			}
		}

		function addInterfaceTags(iface:ClassType):Void {
			final name = fullNameOfClassType(iface);
			if (visited.exists(name)) return;
			add(name);
			for (i in iface.interfaces) addInterfaceTags(i.t.get());
		}

		function addClassTags(c:ClassType):Void {
			final name = fullNameOfClassType(c);
			if (visited.exists(name)) return;
			add(name);
			for (i in c.interfaces) addInterfaceTags(i.t.get());
			if (c.superClass != null) addClassTags(c.superClass.t.get());
		}

		addClassTags(cls);
		return tags;
	}

	function defaultValueForType(t:Type):OcamlExpr {
		final anyNull:OcamlExpr = OcamlExpr.EApp(
			OcamlExpr.EIdent("Obj.magic"),
			[OcamlExpr.EConst(OcamlConst.CUnit)]
		);

		return switch (t) {
			case TAbstract(aRef, params):
				final a = aRef.get();
				switch (a.name) {
					case "Int": OcamlExpr.EConst(OcamlConst.CInt(0));
					case "Float": OcamlExpr.EConst(OcamlConst.CFloat("0."));
					case "Bool": OcamlExpr.EConst(OcamlConst.CBool(false));
					case "Null":
						if (params != null && params.length == 1) {
							switch (params[0]) {
								case TAbstract(pRef, _):
									final p = pRef.get();
									switch (p.name) {
										case "Int", "Float", "Bool":
											OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
										case _:
											anyNull;
									}
								case _:
									anyNull;
							}
						} else {
							anyNull;
						}
					default: anyNull;
				}
			case TInst(cRef, _):
				final c = cRef.get();
				if (c.pack != null && c.pack.length == 0 && c.name == "String") {
					OcamlExpr.EConst(OcamlConst.CString(""));
				} else {
					anyNull;
				}
			case TEnum(_, _):
				anyNull;
			case _:
				anyNull;
		}
	}

	static function orderLetBindingsForOcaml(lets:Array<OcamlLetBinding>):Array<{bindings:Array<OcamlLetBinding>, isRec:Bool}> {
		if (lets.length <= 1) {
			return lets.length == 0
				? []
				: [{ bindings: lets, isRec: isSelfRecursive(lets[0].name, lets[0].expr) }];
		}

		final wantSet:Map<String, Bool> = [];
		final nameToIndex:Map<String, Int> = [];
		for (i in 0...lets.length) {
			final name = lets[i].name;
			wantSet.set(name, true);
			nameToIndex.set(name, i);
		}

		// Build dependency graph (user -> deps).
		final deps:Array<Array<Int>> = [];
		final selfRec:Array<Bool> = [];
		for (i in 0...lets.length) {
			final b = lets[i];
			final depNames = collectFreeIdents(b.expr, wantSet);
			final d:Array<Int> = [];
			var isRec = false;
			for (n in depNames.keys()) {
				final j = nameToIndex.get(n);
				d.push(j);
				if (j == i) isRec = true;
			}
			deps.push(d);
			selfRec.push(isRec);
		}

		// Tarjan SCC.
		final n = lets.length;
		final index:Array<Int> = [];
		final lowlink:Array<Int> = [];
		final onStack:Array<Bool> = [];
		final stack:Array<Int> = [];
		final sccs:Array<Array<Int>> = [];
		for (_ in 0...n) {
			index.push(-1);
			lowlink.push(0);
			onStack.push(false);
		}
		var nextIndex = 0;

		function minInt(a:Int, b:Int):Int return a < b ? a : b;

		function strongconnect(v:Int):Void {
			index[v] = nextIndex;
			lowlink[v] = nextIndex;
			nextIndex++;
			stack.push(v);
			onStack[v] = true;

			for (w in deps[v]) {
				if (index[w] == -1) {
					strongconnect(w);
					lowlink[v] = minInt(lowlink[v], lowlink[w]);
				} else if (onStack[w]) {
					lowlink[v] = minInt(lowlink[v], index[w]);
				}
			}

			if (lowlink[v] == index[v]) {
				final comp:Array<Int> = [];
				while (true) {
					final w = stack.pop();
					onStack[w] = false;
					comp.push(w);
					if (w == v) break;
				}
				sccs.push(comp);
			}
		}

		for (v in 0...n) {
			if (index[v] == -1) strongconnect(v);
		}

		final sccId:Array<Int> = [];
		for (_ in 0...n) sccId.push(-1);
		final sccMinIndex:Array<Int> = [];
		for (sid in 0...sccs.length) {
			var min = 2147483647;
			for (v in sccs[sid]) {
				sccId[v] = sid;
				if (v < min) min = v;
			}
			sccMinIndex.push(min);
		}

		// Condensation graph: dep -> user (so deps appear earlier).
		final adj:Array<Map<Int, Bool>> = [];
		final indeg:Array<Int> = [];
		for (_ in 0...sccs.length) {
			adj.push([]);
			indeg.push(0);
		}

		for (u in 0...n) {
			final su = sccId[u];
			for (v in deps[u]) {
				final sv = sccId[v];
				if (su == sv) continue;
				if (!adj[sv].exists(su)) {
					adj[sv].set(su, true);
					indeg[su] += 1;
				}
			}
		}

		// Kahn topo-sort with stable tie-breaker (min original index).
		final ready:Array<Int> = [];
		for (sid in 0...sccs.length) {
			if (indeg[sid] == 0) ready.push(sid);
		}
		ready.sort((a, b) -> sccMinIndex[a] - sccMinIndex[b]);

		final orderedSccIds:Array<Int> = [];
		while (ready.length > 0) {
			final sid = ready.shift();
			orderedSccIds.push(sid);
			for (to in adj[sid].keys()) {
				indeg[to] -= 1;
				if (indeg[to] == 0) {
					ready.push(to);
					ready.sort((a, b) -> sccMinIndex[a] - sccMinIndex[b]);
				}
			}
		}

		final out:Array<{bindings:Array<OcamlLetBinding>, isRec:Bool}> = [];
		for (sid in orderedSccIds) {
			final nodes = sccs[sid];
			nodes.sort((a, b) -> a - b);
			final groupBindings = nodes.map(i -> lets[i]);
			final rec = nodes.length > 1 || (nodes.length == 1 && selfRec[nodes[0]]);
			out.push({ bindings: groupBindings, isRec: rec });
		}
		return out;
	}

	static function isSelfRecursive(name:String, expr:OcamlExpr):Bool {
		final want:Map<String, Bool> = [];
		want.set(name, true);
		final deps = collectFreeIdents(expr, want);
		return deps.exists(name);
	}

	static function collectFreeIdents(expr:OcamlExpr, want:Map<String, Bool>):Map<String, Bool> {
		final out:Map<String, Bool> = [];
		final bound:Map<String, Int> = [];

		function boundAdd(n:String):Void {
			final c = bound.exists(n) ? bound.get(n) : 0;
			bound.set(n, c + 1);
		}

		function boundRemove(n:String):Void {
			if (!bound.exists(n)) return;
			final c = bound.get(n);
			if (c <= 1) bound.remove(n) else bound.set(n, c - 1);
		}

		function isBound(n:String):Bool return bound.exists(n);

			function collectPatNames(p:OcamlPat, acc:Array<String>):Void {
				switch (p) {
					case PAny:
					case PVar(n):
						acc.push(n);
					case PTuple(items):
						for (i in items) collectPatNames(i, acc);
					case PRecord(fields):
						for (f in fields) collectPatNames(f.pat, acc);
					case PConstructor(_, args):
						for (a in args) collectPatNames(a, acc);
					case POr(items):
						for (i in items) collectPatNames(i, acc);
					case PAnnot(pat, _):
						collectPatNames(pat, acc);
					case PConst(_):
				}
			}

			function visit(e:OcamlExpr):Void {
				switch (e) {
					case EPos(_, inner):
						visit(inner);
					case EConst(_):
					case ERaw(_):
					case EAnnot(expr, _):
						visit(expr);
					case ERaise(exn):
						visit(exn);
					case EIdent(n):
						if (!isBound(n) && want.exists(n)) out.set(n, true);
				case ELet(n, value, body, isRec):
					if (isRec) {
						boundAdd(n);
						visit(value);
						visit(body);
						boundRemove(n);
					} else {
						visit(value);
						boundAdd(n);
						visit(body);
						boundRemove(n);
					}
				case EFun(params, body):
					final names:Array<String> = [];
					for (p in params) collectPatNames(p, names);
					for (n in names) boundAdd(n);
					visit(body);
					for (n in names) boundRemove(n);
				case EApp(fn, args):
					visit(fn);
					for (a in args) visit(a);
				case EAppArgs(fn, args):
					visit(fn);
					for (a in args) visit(a.expr);
				case EBinop(_, l, r):
					visit(l);
					visit(r);
				case EUnop(_, e1):
					visit(e1);
				case EIf(c, t, f):
					visit(c);
					visit(t);
					visit(f);
				case EMatch(scrutinee, cases):
					visit(scrutinee);
					for (c in cases) {
						final names:Array<String> = [];
						collectPatNames(c.pat, names);
						for (n in names) boundAdd(n);
						if (c.guard != null) visit(c.guard);
						visit(c.expr);
						for (n in names) boundRemove(n);
					}
				case ETry(body, cases):
					visit(body);
					for (c in cases) {
						final names:Array<String> = [];
						collectPatNames(c.pat, names);
						for (n in names) boundAdd(n);
						if (c.guard != null) visit(c.guard);
						visit(c.expr);
						for (n in names) boundRemove(n);
					}
				case ESeq(items):
					for (i in items) visit(i);
				case EWhile(c, b):
					visit(c);
					visit(b);
				case EList(items):
					for (i in items) visit(i);
				case ERecord(fields):
					for (f in fields) visit(f.value);
				case EField(e1, _):
					visit(e1);
				case EAssign(_, l, r):
					visit(l);
					visit(r);
				case ETuple(items):
					for (i in items) visit(i);
			}
		}

		visit(expr);
		return out;
	}
}

#end
