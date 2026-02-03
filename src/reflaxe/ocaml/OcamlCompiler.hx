package reflaxe.ocaml;

#if (macro || reflaxe_runtime)

import haxe.io.Path;
#if macro
import haxe.macro.Context;
#end
import haxe.macro.Type;
import haxe.macro.Type.TConstant;
import haxe.macro.Type.TypedExpr;

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
					// Stop at upstream stdlib boundary for now.
					if (isPosInHaxeStd(cur.pos)) break;
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

						// Skip upstream stdlib for now; we only virtualize user/repo classes.
						if (isPosInHaxeStd(c.pos)) continue;
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
		});
		#end
	}

	public override function generateOutputIterator():Iterator<DataAndFileInfo<reflaxe.output.StringOrBytes>> {
		// Ensure type declarations (enums/typedefs/abstracts) appear before value
		// definitions in each module, since OCaml requires constructors/types to
		// be declared before use.
		final all:CompiledCollection<String> = enums.concat(typedefs).concat(abstracts).concat(classes);

		#if macro
		if (!checkedOutputCollisions) {
			checkedOutputCollisions = true;
			assertNoModuleNameCollisions(all);
		}
		#end

		var index = 0;
		return {
			hasNext: () -> index < all.length,
			next: () -> {
				final data = all[index++];
				return data.withOutput(data.data);
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
		if (classType.superClass != null) {
			final sup = classType.superClass.t.get();
			ctx.currentSuperFullName = (sup.pack ?? []).concat([sup.name]).join(".");
			ctx.currentSuperModuleId = sup.module;
			ctx.currentSuperTypeName = sup.name;
		} else {
			ctx.currentSuperFullName = null;
			ctx.currentSuperModuleId = null;
			ctx.currentSuperTypeName = null;
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
		final builder = new OcamlBuilder(ctx);

		// Header marker as a no-op binding to keep output non-empty and debuggable.
		items.push(OcamlModuleItem.ILet([{
			name: "__reflaxe_ocaml__",
			expr: OcamlExpr.EConst(OcamlConst.CUnit)
		}], false));

		final lets:Array<OcamlLetBinding> = [];

		// Instance surface (M5): record type + create + instance methods.
		final instanceVars = varFields.filter(v -> !v.isStatic);
		final hasInstanceVars = instanceVars.length > 0;

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

			final hasInstanceSurface = hasInstanceVars || instanceMethods.length > 0 || ctorFunc != null;
			if (hasInstanceSurface) {
				final instanceTypeName = ctx.scopedInstanceTypeName(classType.module, classType.name);
				final createName = ctx.scopedValueName(classType.module, classType.name, "create");
				final ctorName = ctx.scopedValueName(classType.module, classType.name, "__ctor");

				final isDispatch = (!ctx.currentIsHaxeStd) && !classType.isInterface && ctx.dispatchTypes.exists(fullName);

				// For dynamic dispatch we need a list of all visible instance methods (including inherited)
				// so `obj.foo()` can be lowered to `obj.foo obj ...` regardless of where `foo` was declared.
				final dispatchMethodOrder:Array<String> = [];
				final dispatchMethodDecl:Map<String, { owner:ClassType, field:ClassField }> = [];
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
				}

				final isDispatchInstance = isDispatch && dispatchMethodOrder.length > 0;
				function exprMentionsIdent(e:OcamlExpr, target:String):Bool {
					function any(exprs:Array<OcamlExpr>):Bool {
						for (x in exprs) if (exprMentionsIdent(x, target)) return true;
						return false;
					}
					return switch (e) {
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
				if (hasInstanceVars) {
					for (v in instanceVars) {
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
								// Should not happen for methods; fall back to a permissive type.
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

					final typeDecl:OcamlTypeDecl = {
						name: instanceTypeName,
						params: [],
						kind: (hasInstanceVars || isDispatchInstance)
							? OcamlTypeDeclKind.Record(typeFields)
							: OcamlTypeDeclKind.Alias(OcamlTypeExpr.TIdent("unit"))
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

				final selfInit:OcamlExpr = if (hasInstanceVars || isDispatchInstance) {
					final fields:Array<OcamlRecordField> = [];
					for (v in instanceVars) {
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

						for (name in dispatchMethodOrder) {
							final info = dispatchMethodDecl.get(name);
							if (info == null) continue;
							final owner = info.owner;
							final ownerBinding = ctx.scopedValueName(owner.module, owner.name, name + "__impl");
							final value = wrapperFor(owner, info.field.type, ownerBinding);
							fields.push({ name: name, value: value });
						}
					}

				// Dune defaults can be warning-as-error; avoid `unused-var-strict` for `self`
				// by forcing a use when the body doesn't reference it.
					if (isDispatch && !exprMentionsIdent(ctorBody, "self")) {
						ctorBody = OcamlExpr.ESeq([OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [OcamlExpr.EIdent("self")]), ctorBody]);
					}
					final recordExpr = OcamlExpr.ERecord(fields);
					isDispatchInstance ? OcamlExpr.EAnnot(recordExpr, OcamlTypeExpr.TIdent(instanceTypeName)) : recordExpr;
				} else {
					OcamlExpr.EConst(OcamlConst.CUnit);
				}

			final createBody = OcamlExpr.ELet(
				"self",
				selfInit,
				OcamlExpr.ESeq([ctorBody, OcamlExpr.EIdent("self")]),
				false
			);
			lets.push({ name: createName, expr: OcamlExpr.EFun(createParams, createBody) });

				// Dispatch constructor function (used by `super()` lowering). This intentionally mirrors
				// the constructor body used in `create`, but takes `self` explicitly.
				if (isDispatch) {
					final selfPat = OcamlPat.PAnnot(OcamlPat.PVar("self"), OcamlTypeExpr.TIdent(instanceTypeName));
					lets.push({ name: ctorName, expr: OcamlExpr.EFun([selfPat].concat(createParams), ctorBody) });
				}

			for (f in instanceMethods) {
				final compiled = {
					final argInfo = f.args.map(a -> ({
						id: a.tvar != null ? a.tvar.id : -1,
						name: a.getName()
					}));
						switch (builder.buildFunctionFromArgsAndExpr(argInfo, f.expr)) {
							case OcamlExpr.EFun(params, b):
								final body = (isDispatch && !exprMentionsIdent(b, "self"))
									? OcamlExpr.ESeq([OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [OcamlExpr.EIdent("self")]), b])
									: b;
								OcamlExpr.EFun([OcamlPat.PVar("self")].concat(params), body);
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

		final noDune = haxe.macro.Context.defined("ocaml_no_dune");
		if (!noDune) {
			final duneLibsValue = haxe.macro.Context.definedValue("ocaml_dune_libraries");
			final duneLibs = duneLibsValue == null
				? ["unix"]
				: duneLibsValue
					.split(",")
					.map(s -> StringTools.trim(s))
					.filter(s -> s.length > 0);

			DuneProjectEmitter.emit(output, {
				projectName: DuneProjectEmitter.defaultProjectName(outDir),
				exeName: DuneProjectEmitter.defaultExeName(outDir),
				mainModuleId: mainModuleId,
				duneLibraries: duneLibs
			});
		}

		final noRuntime = haxe.macro.Context.defined("ocaml_no_runtime");
		if (!noRuntime) {
			RuntimeCopier.copy(output, "runtime");
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

		final shouldBuild = !noBuild && !emitOnly;
		final strictBuild = buildMode != null;

		if (!shouldBuild && !shouldRun && buildMode == null) return;

		final exeName = DuneProjectEmitter.defaultExeName(outDir);
		final mode = buildMode != null ? buildMode : "native";

		final result = OcamlBuildRunner.tryBuildAndMaybeRun({
			outDir: outDir,
			exeName: exeName,
			mode: mode,
			run: shouldRun,
			strict: strictBuild
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
					argType = OcamlTypeExpr.TApp("option", [argType]);
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
		final builder = new OcamlBuilder(ctx);
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
			case TAbstract(aRef, _):
				final a = aRef.get();
				switch (a.name) {
					case "Int": OcamlTypeExpr.TIdent("int");
					case "Float": OcamlTypeExpr.TIdent("float");
					case "Bool": OcamlTypeExpr.TIdent("bool");
					case "Void": OcamlTypeExpr.TIdent("unit");
					default: OcamlTypeExpr.TIdent("Obj.t");
				}
			case TInst(cRef, params):
				final c = cRef.get();
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
				} else if (c.isExtern) {
					OcamlTypeExpr.TIdent("Obj.t");
				} else {
					// User class instances are represented by the module's `t` type.
					final modName = moduleIdToOcamlModuleName(c.module);
					final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
					final full = (selfMod != null && selfMod == modName) ? "t" : (modName + ".t");
					OcamlTypeExpr.TIdent(full);
				}
			case TEnum(eRef, params):
				final e = eRef.get();
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
