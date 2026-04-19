#!/usr/bin/env python3
"""Bootstrap patch helper for build-hxhx.sh.

This keeps structural generated-OCaml rewrites out of shell heredocs.
The shell script remains responsible for orchestration; this helper owns
multiline substring and regex-based patching.
"""

from __future__ import annotations

import pathlib
import re
import sys
from typing import Callable, Dict


def read_text(path_str: str) -> str:
    return pathlib.Path(path_str).read_text()


def write_text(path_str: str, text: str) -> None:
    pathlib.Path(path_str).write_text(text)


def fail(message: str) -> "None":
    sys.stderr.write(message)
    raise SystemExit(1)


def replace_one(src: str, old: str, new: str, error: str) -> str:
    if old not in src:
        fail(error)
    return src.replace(old, new, 1)


def cmd_insert_before_anchor(argv: list[str]) -> None:
    if len(argv) != 5:
        fail("usage: insert-before-anchor <emitter_path> <temp_path> <anchor> <patch_path> <error>\n")
    emitter_path, temp_path, anchor, patch_path, error = argv
    src = read_text(emitter_path)
    patch = read_text(patch_path)
    idx = src.find(anchor)
    if idx == -1:
        fail(error + ("\n" if not error.endswith("\n") else ""))
    write_text(temp_path, src[:idx] + patch + src[idx:])


def cmd_patch_array_receiver_chain_lowering(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-array-receiver-chain-lowering <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    map_branch_rx = re.compile(
        r'(\| "map" -> if HxArray.length _g1 = 1 then \(\n'
        r'\s*ignore \(HxArray.get \(Obj\.magic _g1\) 0\);\n'
        r'\s*let inner = Obj\.magic _g2 in )let (__assign_\d+) = \(!isLikelyArrayExpr\) \(Obj\.magic inner\) in \('
    )
    src, map_count = map_branch_rx.subn(r'\1let \2 = (ignore inner; true) in (', src, count=1)
    if map_count != 1:
        fail("build-hxhx: failed to locate array map classifier repair anchor in EmitterStage.ml\n")

    receiver_guard = """if ((!isLikelyArrayExpr) (Obj.magic obj) || (match obj with
                                              | HxExpr.EField (_, _) -> true
                                              | HxExpr.ECast (inner, _) ->
                                                ((!isLikelyArrayExpr) (Obj.magic inner) || (match inner with
                                                  | HxExpr.EField (_, _) -> true
                                                  | _ -> false))
                                              | HxExpr.EUntyped inner ->
                                                ((!isLikelyArrayExpr) (Obj.magic inner) || (match inner with
                                                  | HxExpr.EField (_, _) -> true
                                                  | _ -> false))
                                              | _ -> false)) then"""
    src, guard_count = re.subn(
        r'if \(!isLikelyArrayExpr\) \(Obj\.magic obj\) then',
        receiver_guard,
        src,
    )
    if guard_count == 0:
        fail("build-hxhx: failed to locate array receiver chain lowering guards in EmitterStage.ml\n")

    field_receiver_prefix = """let obj = Obj.magic _g in let field = (_g1 : string) in (
                              ignore (if hasCurrentInstanceMethod (field : string) then match obj with
                                | HxExpr.EThis -> raise (HxRuntime.Hx_return (Obj.repr ((HxString.toStdString (ocamlValueIdent (field : string)) ^ \" (this_)\" : string))))
                                | HxExpr.EIdent _p0 -> ignore (let _g3 = (_p0 : string) in let name = (_g3 : string) in if HxString.equals name \"this\" || HxString.equals name \"this_\" then raise (HxRuntime.Hx_return (Obj.repr ((HxString.toStdString (ocamlValueIdent (field : string)) ^ \" (this_)\" : string)))) else ())
                                | _ -> ignore ()
                              else ());
"""
    field_anchor = "let obj = Obj.magic _g in let field = (_g1 : string) in (\n"
    field_count = src.count(field_anchor)
    src = src.replace(field_anchor, field_receiver_prefix)
    if field_count == 0:
        fail("build-hxhx: failed to locate field receiver repair anchors in EmitterStage.ml\n")

    write_text(path_str, src + "\n(* hxhx(stage3) bootstrap shim: array receiver chain lowering repair *)\n")


def cmd_patch_hxparser_interpolated_exprs(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-hxparser-interpolated-exprs <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    if "let parseInterpolationPayload = fun text ->" in src:
        return

    old = '''          ignore (if !j < HxString.length s && (let __nullable_670 = HxString.charCodeAt s (!j) in if __nullable_670 == HxRuntime.hx_null then false else Obj.obj __nullable_670 = 125) then ignore (let inner = (StringTools.trim (HxString.substr s start (HxInt.sub (!j) start) : string) : string) in if isSimpleIdent (inner : string) then ignore (((
            ignore (HxArray.push parts (HxExpr.EBinop (("+" : string), Obj.magic (HxExpr.EString ("" : string)), Obj.magic (HxExpr.EIdent (inner : string)))));
            ignore (let __assign_671 = HxInt.add (!j) 1 in (
              i := __assign_671;
              __assign_671
            ));
            raise (HxRuntime.Hx_continue)
          )) else ()) else ());'''

    new = '''          ignore (if !j < HxString.length s && (let __nullable_670 = HxString.charCodeAt s (!j) in if __nullable_670 == HxRuntime.hx_null then false else Obj.obj __nullable_670 = 125) then ignore (let inner = (StringTools.trim (HxString.substr s start (HxInt.sub (!j) start) : string) : string) in if HxString.length inner > 0 then ignore (let emitPartAndContinue = fun part -> (
              ignore (HxArray.push parts (Obj.magic part));
              ignore (let __assign_671 = HxInt.add (!j) 1 in (
                i := __assign_671;
                __assign_671
              ));
              raise (HxRuntime.Hx_continue)
            ) in let stringifyIdentExpr = fun name -> HxExpr.EBinop ((("+" : string)), Obj.magic (HxExpr.EString ("" : string)), Obj.magic (HxExpr.EIdent (name : string))) in let rec parseSubsetExpr = fun text -> let trimmed = (StringTools.trim (text : string) : string) in (
              if HxString.length trimmed = 0 then HxExpr.EUnsupported (trimmed : string) else if HxString.length trimmed >= 2 && (let __nullable_quote_start = HxString.charCodeAt trimmed 0 in if __nullable_quote_start == HxRuntime.hx_null then false else Obj.obj __nullable_quote_start = 34) && (let __nullable_quote_end = HxString.charCodeAt trimmed (HxInt.sub (HxString.length trimmed) 1) in if __nullable_quote_end == HxRuntime.hx_null then false else Obj.obj __nullable_quote_end = 34) then HxExpr.EString ((HxString.substr trimmed 1 (HxInt.sub (HxString.length trimmed) 2) : string)) else let splitTopLevelArgs = fun text2 -> let args = Obj.magic (HxArray.create ()) in let depth = ref 0 in let inString = ref false in let startIdx = ref 0 in let idx = ref 0 in (
                ignore (try while !idx < HxString.length text2 do try ignore (let code = HxString.charCodeAt text2 (!idx) in (
                  ignore (if !inString then ignore (((
                    ignore (if (let __nullable_quote = code in if __nullable_quote == HxRuntime.hx_null then false else Obj.obj __nullable_quote = 34) then inString := false else ());
                    ignore (idx := HxInt.add (!idx) 1);
                    raise (HxRuntime.Hx_continue)
                  )) else ());
                  ignore (if (let __nullable_quote = code in if __nullable_quote == HxRuntime.hx_null then false else Obj.obj __nullable_quote = 34) then ignore (((
                    ignore (inString := true);
                    ignore (idx := HxInt.add (!idx) 1);
                    raise (HxRuntime.Hx_continue)
                  )) else ());
                  ignore (if (let __nullable_open = code in if __nullable_open == HxRuntime.hx_null then false else Obj.obj __nullable_open = 40) then ignore (((
                    ignore (depth := HxInt.add (!depth) 1);
                    ignore (idx := HxInt.add (!idx) 1);
                    raise (HxRuntime.Hx_continue)
                  )) else ());
                  ignore (if (let __nullable_close = code in if __nullable_close == HxRuntime.hx_null then false else Obj.obj __nullable_close = 41) then ignore (((
                    ignore (if !depth > 0 then depth := HxInt.sub (!depth) 1 else ());
                    ignore (idx := HxInt.add (!idx) 1);
                    raise (HxRuntime.Hx_continue)
                  )) else ());
                  ignore (if !depth = 0 && (let __nullable_comma = code in if __nullable_comma == HxRuntime.hx_null then false else Obj.obj __nullable_comma = 44) then ignore (let chunk = (StringTools.trim (HxString.substr text2 (!startIdx) (HxInt.sub (!idx) (!startIdx)) : string) : string) in (
                    ignore (if HxString.length chunk > 0 then ignore (HxArray.push args (chunk : string)) else ignore ());
                    ignore (startIdx := HxInt.add (!idx) 1);
                    ignore (idx := HxInt.add (!idx) 1);
                    raise (HxRuntime.Hx_continue)
                  )) else ());
                  ignore (idx := HxInt.add (!idx) 1)
                )) with
                  | HxRuntime.Hx_continue -> () done with
                  | HxRuntime.Hx_break -> ());
                let tail = (StringTools.trim (HxString.substr text2 (!startIdx) (HxInt.sub (HxString.length text2) (!startIdx)) : string) : string) in (
                  ignore (if HxString.length tail > 0 then ignore (HxArray.push args (tail : string)) else ignore ());
                  args
                )
              ) in let parsePathExpr = fun text2 -> let currentIndex = ref 0 in let segmentCount = ref 0 in let valid = ref true in let out = ref (Obj.magic (HxRuntime.hx_null) : Obj.t) in let rec loop = fun () -> if !valid && !currentIndex < HxString.length text2 then (
                let code = HxString.charCodeAt text2 (!currentIndex) in (
                  if not (let __nullable_code = code in if __nullable_code == HxRuntime.hx_null then false else isIdentStart (Obj.obj __nullable_code)) then valid := false else let startIndex = !currentIndex in (
                    ignore (let __old_path_index = !currentIndex in let __new_path_index = HxInt.add __old_path_index 1 in (
                      ignore (currentIndex := __new_path_index);
                      __old_path_index
                    ));
                    ignore (while !currentIndex < HxString.length text2 && isIdentCont (let __nullable_seg = HxString.charCodeAt text2 (!currentIndex) in if __nullable_seg == HxRuntime.hx_null then 0 else Obj.obj __nullable_seg) do ignore (let __old_seg_index = !currentIndex in let __new_seg_index = HxInt.add __old_seg_index 1 in (
                      ignore (currentIndex := __new_seg_index);
                      __old_seg_index
                    )) done);
                    let segment = (HxString.substr text2 startIndex (HxInt.sub (!currentIndex) startIndex) : string) in (
                      ignore (if !segmentCount = 0 then out := Obj.repr (HxExpr.EIdent (segment : string)) else out := Obj.repr (HxExpr.EField (Obj.magic (Obj.obj (!out)), (segment : string))));
                      ignore (segmentCount := HxInt.add (!segmentCount) 1)
                    );
                    ignore (if !currentIndex < HxString.length text2 then ignore (if (let __nullable_dot = HxString.charCodeAt text2 (!currentIndex) in if __nullable_dot == HxRuntime.hx_null then false else Obj.obj __nullable_dot = 46) then ignore (let __old_dot = !currentIndex in let __new_dot = HxInt.add __old_dot 1 in (
                      ignore (currentIndex := __new_dot);
                      __old_dot
                    )) else valid := false) else ())
                  )
                );
                loop ()
              ) else () in (
                ignore (loop ());
                if !valid && !segmentCount > 0 then Obj.magic (Obj.obj (!out)) else HxExpr.EUnsupported (text2 : string)
              ) in let openIndex = HxString.indexOf trimmed "(" 0 in (
                if openIndex <> -1 && (let __nullable_last = HxString.charCodeAt trimmed (HxInt.sub (HxString.length trimmed) 1) in if __nullable_last == HxRuntime.hx_null then false else Obj.obj __nullable_last = 41) then let calleeText = (StringTools.trim (HxString.substr trimmed 0 openIndex : string) : string) in let argsText = (HxString.substr trimmed (HxInt.add openIndex 1) (HxInt.sub (HxInt.sub (HxString.length trimmed) openIndex) 2) : string) in let calleeExpr = Obj.magic (parsePathExpr (calleeText : string)) in (
                  match calleeExpr with
                  | HxExpr.EUnsupported _ -> calleeExpr
                  | _ ->
                    let parsedArgs = Obj.magic (HxArray.create ()) in let rawArgs = Obj.magic (splitTopLevelArgs (argsText : string)) in let ok = ref true in (
                      ignore (let _g_arg = ref 0 in let _g_arg_max = HxArray.length rawArgs in while !_g_arg < _g_arg_max do ignore (let rawArg = HxArray.get (Obj.magic rawArgs) (!_g_arg) in (
                        ignore (let __old_arg_index = !_g_arg in let __new_arg_index = HxInt.add __old_arg_index 1 in (
                          ignore (_g_arg := __new_arg_index);
                          __new_arg_index
                        ));
                        ignore (if !ok then let parsedArg = Obj.magic (parseSubsetExpr (rawArg : string)) in (
                          match parsedArg with
                          | HxExpr.EUnsupported _ -> ok := false
                          | _ -> ignore (HxArray.push parsedArgs (Obj.magic parsedArg))
                        ) else ())
                      )) done);
                      if !ok then HxExpr.ECall (Obj.magic calleeExpr, Obj.magic parsedArgs) else HxExpr.EUnsupported (trimmed : string)
                    )
                ) else parsePathExpr (trimmed : string)
              )
            ) in let parsedInner = Obj.magic (parseSubsetExpr (inner : string)) in (
              match parsedInner with
              | HxExpr.EUnsupported _ ->
                if isSimpleIdent (inner : string) then emitPartAndContinue (stringifyIdentExpr (inner : string)) else emitPartAndContinue (HxExpr.EString (((("${" : string) ^ inner) ^ ("}" : string) : string)))
              | HxExpr.EIdent _p0 ->
                let name = (_p0 : string) in emitPartAndContinue (stringifyIdentExpr (name : string))
              | _ ->
                emitPartAndContinue (Obj.magic parsedInner)
            )) else ()) else ());
          (* hxhx(stage3) bootstrap shim: HxParser interpolation expr repair *)'''

    old = old.replace("ignore (((\n", "ignore ((\n")
    new = new.replace("ignore (((\n", "ignore ((\n")
    new = new.replace('HxExpr.EBinop ((("+" : string)),', 'HxExpr.EBinop (("+" : string),')

    if old in src:
        write_text(path_str, src.replace(old, new, 1))
        return

    legacy_rx = re.compile(
        r'''          ignore \(if !j < HxString.length s && \(let __nullable_\d+ = HxString\.charCodeAt s \(!j\) in if __nullable_\d+ == HxRuntime\.hx_null then false else Obj\.obj __nullable_\d+ = 125\) then ignore \(let inner = \(StringTools\.trim \(HxString\.substr s start \(HxInt\.sub \(!j\) start\) : string\) : string\) in if isSimpleIdent \(inner : string\) then ignore \(\(.*?raise \(HxRuntime\.Hx_continue\)\n\s*\)\) else \(\)\) else \(\)\);''',
        re.S,
    )
    replaced, count = legacy_rx.subn(new, src, count=1)
    if count != 1:
        fail("build-hxhx: failed to locate bootstrap HxParser interpolation repair anchor\n")
    write_text(path_str, replaced)


def cmd_patch_hxparser_generic_function_decl(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-hxparser-generic-function-decl <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    helper_anchor = """let lambdaBodyExprFromStmts = fun self (stmts : HxStmt.hxstmt HxArray.t) -> ("""
    helper_text = """let skipBalancedAngles = fun self () ->
  let rec loop depth =
    let _g = Obj.magic ((Obj.magic ((Obj.magic self : t).cur) : HxToken.t).kind) in
    match _g with
    | HxTokenKind.TEof -> ignore (fail (Obj.magic self) ("Unterminated angle bracket group" : string))
    | HxTokenKind.TOther c ->
        if c = 45 && (match peekKind (Obj.magic self) () with
          | HxTokenKind.TOther c2 -> c2 = 62
          | _ -> false) then (
          ignore (bump (Obj.magic self) ());
          ignore (bump (Obj.magic self) ());
          loop depth
        ) else if c = 60 then (
          ignore (bump (Obj.magic self) ());
          loop (depth + 1)
        ) else if c = 62 then (
          ignore (bump (Obj.magic self) ());
          if depth <= 1 then () else loop (depth - 1)
        ) else (
          ignore (bump (Obj.magic self) ());
          loop depth
        )
    | HxTokenKind.TLParen ->
        ignore (bump (Obj.magic self) ());
        ignore (skipBalancedParens (Obj.magic self) ());
        loop depth
    | HxTokenKind.TLBrace ->
        ignore (bump (Obj.magic self) ());
        ignore (skipBalancedBraces (Obj.magic self) ());
        loop depth
    | _ ->
        ignore (bump (Obj.magic self) ());
        loop depth
  in
  loop 0

"""

    if (
        "let skipBalancedAngles = fun self () ->" in src
        and 'ignore (if isOtherChar (Obj.magic self) ("<" : string) then ignore (skipBalancedAngles (Obj.magic self) ()) else ());' in src
    ):
        write_text(path_str, src)
        return

    if "let skipBalancedAngles = fun self () ->" not in src:
        if helper_anchor not in src:
            fail("build-hxhx: failed to locate bootstrap HxParser helper insertion anchor\n")
        src = src.replace(helper_anchor, helper_text + helper_anchor, 1)

    old = """    ) else let __assign_2535 = (readIdent (Obj.magic self) ("function name" : string) : string) in (
      tempString := __assign_2535;
      __assign_2535
    ));
    ignore (expect (Obj.magic self) (Obj.magic (HxTokenKind.TLParen)) ("'('" : string));"""

    new = """    ) else let __assign_2535 = (readIdent (Obj.magic self) ("function name" : string) : string) in (
      tempString := __assign_2535;
      __assign_2535
    ));
    ignore (if isOtherChar (Obj.magic self) ("<" : string) then skipBalancedAngles (Obj.magic self) () else ());
    ignore (expect (Obj.magic self) (Obj.magic (HxTokenKind.TLParen)) ("'('" : string));"""

    if old not in src:
        fail("build-hxhx: failed to locate bootstrap HxParser generic-function repair anchor\n")
    write_text(path_str, src.replace(old, new, 1))


def cmd_patch_hxparser_uppercase_helper_call(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-hxparser-uppercase-helper-call <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    old = """        if isUpperStart (name : string) && not (!tempBool) && hasLowerAlpha (name : string) then let __assign_363 = Obj.magic (HxExpr.EEnumValue (name : string)) in (
          tempResult := __assign_363;
          __assign_363
        ) else let __assign_364 = Obj.magic (HxExpr.EIdent (name : string)) in (
          tempResult := __assign_364;
          __assign_364
        )"""

    new = """        if isUpperStart (name : string) && not (!tempBool) && hasLowerAlpha (name : string) && HxString.indexOf name "_" 0 = -1 then let __assign_363 = Obj.magic (HxExpr.EEnumValue (name : string)) in (
          tempResult := __assign_363;
          __assign_363
        ) else let __assign_364 = Obj.magic (HxExpr.EIdent (name : string)) in (
          tempResult := __assign_364;
          __assign_364
        )"""

    if old in src:
        write_text(path_str, src.replace(old, new, 1))
        return

    legacy_rx = re.compile(
        r'''        if isUpperStart \(name : string\) && not \(!tempBool\) && hasLowerAlpha \(name : string\) then let __assign_\d+ = Obj\.magic \(HxExpr\.EEnumValue \(name : string\)\) in \(\n          tempResult := __assign_\d+;\n          __assign_\d+\n        \) else let __assign_\d+ = Obj\.magic \(HxExpr\.EIdent \(name : string\)\) in \(\n          tempResult := __assign_\d+;\n          __assign_\d+\n        \)''',
        re.S,
    )
    replaced, count = legacy_rx.subn(new, src, count=1)
    if count != 1:
        fail("build-hxhx: failed to locate bootstrap HxParser uppercase-helper-call anchor\n")
    write_text(path_str, replaced)


def cmd_patch_native_parser_generic_arrow_constraints(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-native-parser-generic-arrow-constraints <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    old = """      while !depth_a > 0 do
        match cur () with
        | Eof p -> raise (Parse_error (p, "unterminated angle bracket group"))
        | Sym ('<', _) ->
            depth_a := !depth_a + 1;
            bump ()
        | Sym ('>', _) ->
            depth_a := !depth_a - 1;
            bump ()
        | _ -> bump ()
      done"""

    new = """      while !depth_a > 0 do
        match cur () with
        | Eof p -> raise (Parse_error (p, "unterminated angle bracket group"))
        | Sym ('-', _) when token_eq_sym (peek 1) '>' ->
            (* Function type arrows inside generic constraints, e.g.
                 Constructible<String -> Void>
               must not consume the generic depth. *)
            bump ();
            bump ()
        | Sym ('<', _) ->
            depth_a := !depth_a + 1;
            bump ()
        | Sym ('>', _) ->
            depth_a := !depth_a - 1;
            bump ()
        | _ -> bump ()
      done"""

    if old not in src:
        fail("build-hxhx: failed to locate bootstrap native parser generic-arrow anchor\n")
    write_text(path_str, src.replace(old, new, 1))


def cmd_patch_native_parser_expr_spacing(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-native-parser-expr-spacing <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    helper_anchor = """let starts_with (s : string) (prefix : string) : bool =
  let sl = Stdlib.String.length s in
  let pl = Stdlib.String.length prefix in
  sl >= pl && Stdlib.String.sub s 0 pl = prefix
"""
    helper_insert = """let starts_with (s : string) (prefix : string) : bool =
  let sl = Stdlib.String.length s in
  let pl = Stdlib.String.length prefix in
  sl >= pl && Stdlib.String.sub s 0 pl = prefix

let is_word_char (c : char) : bool =
  match c with
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> true
  | _ -> false

let append_token_text (b : Buffer.t) (text : string) : unit =
  if text <> "" then (
    if Buffer.length b > 0 then (
      let prev = Buffer.nth b (Buffer.length b - 1) in
      let next = Stdlib.String.get text 0 in
      let prev_needs_space =
        is_word_char prev || prev = ')' || prev = ']' || prev = '}' || prev = '"'
      in
      let next_needs_space = is_word_char next || next = '"' || next = '~' in
      let prev_forbids_space =
        prev = '.' || prev = ':' || prev = '(' || prev = '[' || prev = '{' || prev = ','
      in
      if prev_needs_space && next_needs_space && not prev_forbids_space then
        Buffer.add_char b ' ');
    Buffer.add_string b text)
"""
    if "let append_token_text (b : Buffer.t) (text : string) : unit =" not in src:
        if helper_anchor not in src:
            fail("build-hxhx: failed to locate bootstrap native parser expr-spacing helper anchor\n")
        src = src.replace(helper_anchor, helper_insert, 1)

    old = "Buffer.add_string parts (tok_to_text tok);"
    new = "append_token_text parts (tok_to_text tok);"
    count = src.count(old)
    if count < 3:
        fail("build-hxhx: failed to locate bootstrap native parser expr-spacing append anchors\n")
    src = src.replace(old, new)
    write_text(path_str, src)


def cmd_patch_emitter_typed_param_fallback(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-emitter-typed-param-fallback <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    old = """let args = Obj.magic (TyFunctionEnv.getParams (Obj.magic tf) ()) in let parsedFn = Obj.magic (HxMap.get_string parsedByName nameRaw) in """
    new = """let args = Obj.magic (TyFunctionEnv.getParams (Obj.magic tf) ()) in let parsedFn = Obj.magic (HxMap.get_string parsedByName nameRaw) in let args = if HxArray.length args = 0 && parsedFn != Obj.magic (HxRuntime.hx_null) then let parsedArgs = Obj.magic (HxFunctionDecl.getArgs (Obj.magic parsedFn)) in if HxArray.length parsedArgs = 0 then Obj.magic args else Obj.magic (let __arr_bootstrap_fn_args = HxArray.create () in (
                                                                    ignore (let _g_bootstrap_fn_arg = ref 0 in while !_g_bootstrap_fn_arg < HxArray.length parsedArgs do ignore (let parsedArg = Obj.magic (HxArray.get (Obj.magic parsedArgs) (!_g_bootstrap_fn_arg)) in (
                                                                      ignore (let __old_bootstrap_fn_arg = !_g_bootstrap_fn_arg in let __new_bootstrap_fn_arg = HxInt.add __old_bootstrap_fn_arg 1 in (
                                                                        ignore (_g_bootstrap_fn_arg := __new_bootstrap_fn_arg);
                                                                        __new_bootstrap_fn_arg
                                                                      ));
                                                                      let parsedName = (HxFunctionArg.getName (Obj.magic parsedArg) : string) in let parsedTy = Obj.magic (TyType.fromHintText (HxFunctionArg.getTypeHint (Obj.magic parsedArg) : string)) in (
                                                                        ignore (HxArray.push __arr_bootstrap_fn_args (Obj.magic (TySymbol.create (parsedName : string) (Obj.magic parsedTy))))
                                                                      )
                                                                    )) done);
                                                                    __arr_bootstrap_fn_args
                                                                  )) else Obj.magic args in (* hxhx(stage3) bootstrap shim: typed param fallback for emitted fn args *) """

    src, count = src.replace(old, new), src.count(old)
    if count == 0:
        fail("build-hxhx: failed to locate bootstrap typed-param fallback anchor in EmitterStage.ml\n")
    write_text(path_str, src)


def cmd_patch_emitter_parsed_arg_type_overlay(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-emitter-parsed-arg-type-overlay <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    if "bootstrap shim: typed param fallback for emitted fn args" in src:
        return

    old = """                                                                    ignore (let _g2 = ref 0 in while !_g2 < HxArray.length args do ignore (let a = Obj.magic (HxArray.get (Obj.magic args) (!_g2)) in (
                                                                      ignore (let __old_46869 = !_g2 in let __new_46870 = HxInt.add __old_46869 1 in (
                                                                        ignore (_g2 := __new_46870);
                                                                        __new_46870
                                                                      ));
                                                                      let key = (TySymbol.getName (Obj.magic a) () : string) in let value = Obj.magic (TySymbol.getType (Obj.magic a) ()) in HxMap.set_string tyByIdent key value
                                                                    )) done);
"""
    new = """                                                                    ignore (let _g2 = ref 0 in while !_g2 < HxArray.length args do ignore (let a = Obj.magic (HxArray.get (Obj.magic args) (!_g2)) in (
                                                                      ignore (let __old_46869 = !_g2 in let __new_46870 = HxInt.add __old_46869 1 in (
                                                                        ignore (_g2 := __new_46870);
                                                                        __new_46870
                                                                      ));
                                                                      let key = (TySymbol.getName (Obj.magic a) () : string) in let value = Obj.magic (TySymbol.getType (Obj.magic a) ()) in HxMap.set_string tyByIdent key value
                                                                    )) done);
                                                                    ignore (if parsedFn != Obj.magic (HxRuntime.hx_null) then ignore (let parsedArgs = Obj.magic (HxFunctionDecl.getArgs (Obj.magic parsedFn)) in let _g_bootstrap_arg_hint = ref 0 in while !_g_bootstrap_arg_hint < HxArray.length parsedArgs do ignore (let parsedArg = Obj.magic (HxArray.get (Obj.magic parsedArgs) (!_g_bootstrap_arg_hint)) in (
                                                                      let idx = !_g_bootstrap_arg_hint in (
                                                                        ignore (let __old_bootstrap_arg_hint = !_g_bootstrap_arg_hint in let __new_bootstrap_arg_hint = HxInt.add __old_bootstrap_arg_hint 1 in (
                                                                          ignore (_g_bootstrap_arg_hint := __new_bootstrap_arg_hint);
                                                                          __new_bootstrap_arg_hint
                                                                        ));
                                                                        let typedArg = if idx < HxArray.length args then Obj.magic (HxArray.get (Obj.magic args) idx) else Obj.magic (HxRuntime.hx_null) in let typedName = if typedArg == Obj.magic (HxRuntime.hx_null) then ("" : string) else (TySymbol.getName (Obj.magic typedArg) () : string) in let parsedName = (HxFunctionArg.getName (Obj.magic parsedArg) : string) in let hinted = Obj.magic (TyType.fromHintText (HxFunctionArg.getTypeHint (Obj.magic parsedArg) : string)) in (
                                                                          ignore (if typedName != Obj.magic (HxRuntime.hx_null) && HxString.length typedName > 0 then ignore (let existing = Obj.magic (HxMap.get_string tyByIdent typedName) in let existingNeedsRepair = existing == Obj.magic (HxRuntime.hx_null) || TyType.isUnknown (Obj.magic existing) () || HxString.equals (TyType.toString (Obj.magic existing) ()) "Dynamic" || HxString.equals (TyType.toString (Obj.magic existing) ()) "Array" || not (HxString.equals (TyType.toString (Obj.magic existing) ()) (TyType.toString (Obj.magic hinted) ())) in let hintedUseful = hinted != Obj.magic (HxRuntime.hx_null) && not (TyType.isUnknown (Obj.magic hinted) ()) && not (HxString.equals (TyType.toString (Obj.magic hinted) ()) "Dynamic") in if existingNeedsRepair && hintedUseful then ignore (HxMap.set_string tyByIdent typedName hinted) else ()) else ());
                                                                          ignore (if parsedName != Obj.magic (HxRuntime.hx_null) && HxString.length parsedName > 0 && not (HxString.equals parsedName typedName) then ignore (let existing = Obj.magic (HxMap.get_string tyByIdent parsedName) in let existingNeedsRepair = existing == Obj.magic (HxRuntime.hx_null) || TyType.isUnknown (Obj.magic existing) () || HxString.equals (TyType.toString (Obj.magic existing) ()) "Dynamic" || HxString.equals (TyType.toString (Obj.magic existing) ()) "Array" || not (HxString.equals (TyType.toString (Obj.magic existing) ()) (TyType.toString (Obj.magic hinted) ())) in let hintedUseful = hinted != Obj.magic (HxRuntime.hx_null) && not (TyType.isUnknown (Obj.magic hinted) ()) && not (HxString.equals (TyType.toString (Obj.magic hinted) ()) "Dynamic") in if existingNeedsRepair && hintedUseful then ignore (HxMap.set_string tyByIdent parsedName hinted) else ()) else ())
                                                                        )
                                                                      )
                                                                    )) done) else ());
                                                                    (* hxhx(stage3) bootstrap shim: parsed arg type overlay for tyByIdent *)
"""

    if old in src:
        write_text(path_str, src.replace(old, new, 1))
        return

    legacy_rx = re.compile(
        r'''ignore \(let _g2 = ref 0 in while !_g2 < HxArray.length args do ignore \(let a = Obj\.magic \(HxArray\.get \(Obj\.magic args\) \(!_g2\)\) in \(.*?HxMap\.set_string tyByIdent key value\s*\)\) done\);\n''',
        re.S,
    )
    replaced, count = legacy_rx.subn(new, src, count=1)
    if count != 1:
        fail("build-hxhx: failed to locate bootstrap parsed-arg type overlay anchor in EmitterStage.ml\n")
    write_text(path_str, replaced)


def cmd_patch_emitter_preapplied_sig_fallback(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-emitter-preapplied-sig-fallback <path>\n")
    path_str = argv[0]
    src = read_text(path_str)
    if "receiverPreApplied" not in src and "!hx_sig" not in src:
        return

    old = "ignore (if Obj.magic (!hx_sig) == Obj.magic (HxRuntime.hx_null) && not (receiverPreApplied) then ignore (let firstSpace = HxString.indexOf c \" \" 0 in ("
    new = "ignore (if Obj.magic (!hx_sig) == Obj.magic (HxRuntime.hx_null) then ignore (let firstSpace = HxString.indexOf c \" \" 0 in ("

    count = src.count(old)
    if count == 0:
        fail("build-hxhx: failed to locate bootstrap preapplied-signature fallback anchors in EmitterStage.ml\n")
    write_text(path_str, src.replace(old, new))


def cmd_patch_stage1_std_root_termination(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-stage1-std-root-termination <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    old = """        let __assign_37 = (Haxe_io_Path.normalize (Haxe_io_Path.join (Obj.magic (let __arr_38 = HxArray.create () in (
          ignore (HxArray.push __arr_38 (!dir));
          ignore (HxArray.push __arr_38 "..");
          __arr_38
        ))) : string) : string) in (
          dir := __assign_37;
          __assign_37
        )"""

    new = """        let nextDir = (Haxe_io_Path.normalize (Haxe_io_Path.join (Obj.magic (let __arr_38 = HxArray.create () in (
          ignore (HxArray.push __arr_38 (!dir));
          ignore (HxArray.push __arr_38 "..");
          __arr_38
        ))) : string) : string) in (
          let __assign_37 = (if nextDir == Obj.magic (HxRuntime.hx_null) || HxString.length nextDir = 0 || HxString.equals nextDir "." || HxString.equals nextDir ".." || StringTools.startsWith (nextDir : string) ("../" : string) then (!dir : string) else (nextDir : string)) in (
            dir := __assign_37;
            __assign_37
          )
        )"""

    if old not in src:
        fail("build-hxhx: failed to locate bootstrap Stage1 std-root repair anchor\n")
    write_text(path_str, src.replace(old, new, 1))


def cmd_patch_allowed_ident_fallback(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-allowed-ident-fallback <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    backend_anchor = 'let backendDialect = Obj.magic (HihOcamlBackendDialect.create ())'
    backend_insert = '''let currentAllowedValueIdentNames = ref (Obj.magic (HxRuntime.hx_null) : bool HxMap.string_map)

let hasAllowedValueIdent = fun name -> !currentAllowedValueIdentNames != Obj.magic (HxRuntime.hx_null) && (let __nullable_allowed = HxMap.get_string (!currentAllowedValueIdentNames) name in if __nullable_allowed == HxRuntime.hx_null then false else Obj.obj __nullable_allowed = true)

let backendDialect = Obj.magic (HihOcamlBackendDialect.create ())'''

    injected_helper_defs = False
    if 'hasAllowedValueIdent (' in src and 'let hasAllowedValueIdent = fun name' not in src:
        if backend_anchor not in src:
            return
        src = src.replace(backend_anchor, backend_insert, 1)
        injected_helper_defs = True

    old_ident_branch = '''                              if mapGetRaw (Obj.repr tyByIdent) (!tempString5 : string) != Obj.magic (HxRuntime.hx_null) then let __assign_399 = (ocamlReadValueIdent (name : string) : string) in (
                                tempResult13 := __assign_399;
                                __assign_399
                              ) else if mapHasRaw (Obj.repr arityByIdent) (name : string) then let __assign_400 = (ocamlValueIdent (name : string) : string) in (
                                tempResult13 := __assign_400;
                                __assign_400
                              ) else let tempLeft = ref ("" : string) in ('''
    if old_ident_branch not in src:
        # Current bootstrap snapshots already carry the newer ident-resolution shape,
        # so the legacy allowed-ident fallback repair is obsolete.
        if injected_helper_defs:
            write_text(path_str, src)
        return

    new_ident_branch = '''                              if mapGetRaw (Obj.repr tyByIdent) (!tempString5 : string) != Obj.magic (HxRuntime.hx_null) then let __assign_399 = (ocamlReadValueIdent (name : string) : string) in (
                                tempResult13 := __assign_399;
                                __assign_399
                              ) else if hasAllowedValueIdent (name : string) then let __assign_bootstrap_allowed_ident = (ocamlReadValueIdent (name : string) : string) in (
                                tempResult13 := __assign_bootstrap_allowed_ident;
                                __assign_bootstrap_allowed_ident
                              ) else if mapHasRaw (Obj.repr arityByIdent) (name : string) then let __assign_400 = (ocamlValueIdent (name : string) : string) in (
                                tempResult13 := __assign_400;
                                __assign_400
                              ) else let tempLeft = ref ("" : string) in ('''
    src = src.replace(old_ident_branch, new_ident_branch, 1)

    old_body_prefix = '''                                                                              let tempString45 = ref ("" : string) in (
                                                                                ignore (if parsedFn == Obj.magic (HxRuntime.hx_null) then let __assign_46901 = ("()" : string) in ('''
    new_body_prefix = '''                                                                              let prevAllowedValueIdentNames = (!currentAllowedValueIdentNames : bool HxMap.string_map) in let _bootstrap_allowed_assign = let __assign_bootstrap_allowed_names = Obj.magic allowed in (
                                                                                currentAllowedValueIdentNames := __assign_bootstrap_allowed_names;
                                                                                __assign_bootstrap_allowed_names
                                                                              ) in let tempString45 = ref ("" : string) in (
                                                                                ignore _bootstrap_allowed_assign;
                                                                                ignore (if parsedFn == Obj.magic (HxRuntime.hx_null) then let __assign_46901 = ("()" : string) in ('''
    if old_body_prefix not in src:
        fail("build-hxhx: failed to locate bootstrap function-body prefix for allowed-ident repair\n")
    src = src.replace(old_body_prefix, new_body_prefix, 1)

    old_body_restore = '''                                                                                let body = ref (!tempString45 : string) in (
                                                                                  ignore (if HxString.equals mainModuleName "Haxe_ds_EnumValueMap"'''
    new_body_restore = '''                                                                                let body = ref (!tempString45 : string) in (
                                                                                  ignore (let __assign_bootstrap_restore_allowed = prevAllowedValueIdentNames in (
                                                                                    currentAllowedValueIdentNames := __assign_bootstrap_restore_allowed;
                                                                                    __assign_bootstrap_restore_allowed
                                                                                  ));
                                                                                  ignore (if HxString.equals mainModuleName "Haxe_ds_EnumValueMap"'''
    if old_body_restore not in src:
        fail("build-hxhx: failed to locate bootstrap function-body restore point for allowed-ident repair\n")
    src = src.replace(old_body_restore, new_body_restore, 1)

    static_loop_anchor = 'let staticTyByIdent = HxMap.create_string () in ('
    static_loop_repl = 'let staticTyByIdent = HxMap.create_string () in let staticAllowedValueIdents = HxMap.create_string () in ('
    if src.count(static_loop_anchor) < 2:
        fail("build-hxhx: failed to locate bootstrap static-init anchors for allowed-ident repair\n")
    src = src.replace(static_loop_anchor, static_loop_repl, 2)

    old_stub_init = '''                                                  ignore (if init == Obj.magic (HxRuntime.hx_null) then let __assign_46664 = ("(Obj.magic HxRuntime.hx_null)" : string) in (
                                                    tempString36 := __assign_46664;
                                                    __assign_46664
                                                  ) else let __assign_46665 = (exprToOcaml (Obj.obj (HxEnum.unbox_or_obj "HxExpr" init)) (HxRuntime.hx_null) (Obj.repr staticTyByIdent) (HxRuntime.hx_null) (HxModuleDecl.getPackagePath (Obj.magic decl) : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr globalCallSigByCallee) : string) in (
                                                    tempString36 := __assign_46665;
                                                    __assign_46665
                                                  ));'''
    new_stub_init = '''                                                  ignore (let prevAllowedValueIdentNames = (!currentAllowedValueIdentNames : bool HxMap.string_map) in (
                                                    ignore (currentAllowedValueIdentNames := staticAllowedValueIdents);
                                                    ignore (if init == Obj.magic (HxRuntime.hx_null) then let __assign_46664 = ("(Obj.magic HxRuntime.hx_null)" : string) in (
                                                      tempString36 := __assign_46664;
                                                      __assign_46664
                                                    ) else let __assign_46665 = (exprToOcaml (Obj.obj (HxEnum.unbox_or_obj "HxExpr" init)) (HxRuntime.hx_null) (Obj.repr staticTyByIdent) (HxRuntime.hx_null) (HxModuleDecl.getPackagePath (Obj.magic decl) : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr globalCallSigByCallee) : string) in (
                                                      tempString36 := __assign_46665;
                                                      __assign_46665
                                                    ));
                                                    currentAllowedValueIdentNames := prevAllowedValueIdentNames
                                                  ));'''
    if old_stub_init not in src:
        fail("build-hxhx: failed to locate bootstrap stub static-init exprToOcaml anchor for allowed-ident repair\n")
    src = src.replace(old_stub_init, new_stub_init, 1)

    old_stub_after = '''                                                  let initOcaml = (!tempString36 : string) in (
                                                    ignore (HxArray.push out ((("let " ^ HxString.toStdString (ocamlValueIdent (nameRaw : string))) ^ " = ") ^ HxString.toStdString initOcaml));
                                                    ignore (HxArray.push out "");
                                                    let knownType = Obj.magic (HxMap.get_string staticTyByIdent nameRaw) in if knownType == Obj.magic (HxRuntime.hx_null) || TyType.isUnknown (Obj.magic knownType) () && not (TyType.isUnknown (Obj.magic inferredType) ()) then ignore (HxMap.set_string staticTyByIdent nameRaw inferredType) else ()'''
    new_stub_after = '''                                                  let initOcaml = (!tempString36 : string) in (
                                                    ignore (HxArray.push out ((("let " ^ HxString.toStdString (ocamlValueIdent (nameRaw : string))) ^ " = ") ^ HxString.toStdString initOcaml));
                                                    ignore (HxArray.push out "");
                                                    ignore (HxMap.set_string staticAllowedValueIdents nameRaw true);
                                                    let knownType = Obj.magic (HxMap.get_string staticTyByIdent nameRaw) in if knownType == Obj.magic (HxRuntime.hx_null) || TyType.isUnknown (Obj.magic knownType) () && not (TyType.isUnknown (Obj.magic inferredType) ()) then ignore (HxMap.set_string staticTyByIdent nameRaw inferredType) else ()'''
    if old_stub_after not in src:
        fail("build-hxhx: failed to locate bootstrap stub static-init post-bind anchor for allowed-ident repair\n")
    src = src.replace(old_stub_after, new_stub_after, 1)

    old_main_init = '''                                                                            ignore (if init == Obj.magic (HxRuntime.hx_null) then let __assign_46910 = ("(Obj.magic 0)" : string) in (
                                                                              tempString47 := __assign_46910;
                                                                              __assign_46910
                                                                            ) else let __assign_46911 = (exprToOcaml (Obj.obj (HxEnum.unbox_or_obj "HxExpr" init)) (Obj.repr arityByName) (Obj.repr staticTyByIdent) (Obj.repr staticImportByIdent) (HxModuleDecl.getPackagePath (Obj.magic decl) : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee) : string) in (
                                                                              tempString47 := __assign_46911;
                                                                              __assign_46911
                                                                            ));'''
    new_main_init = '''                                                                            ignore (let prevAllowedValueIdentNames = (!currentAllowedValueIdentNames : bool HxMap.string_map) in (
                                                                              ignore (currentAllowedValueIdentNames := staticAllowedValueIdents);
                                                                              ignore (if init == Obj.magic (HxRuntime.hx_null) then let __assign_46910 = ("(Obj.magic 0)" : string) in (
                                                                                tempString47 := __assign_46910;
                                                                                __assign_46910
                                                                              ) else let __assign_46911 = (exprToOcaml (Obj.obj (HxEnum.unbox_or_obj "HxExpr" init)) (Obj.repr arityByName) (Obj.repr staticTyByIdent) (Obj.repr staticImportByIdent) (HxModuleDecl.getPackagePath (Obj.magic decl) : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee) : string) in (
                                                                                tempString47 := __assign_46911;
                                                                                __assign_46911
                                                                              ));
                                                                              currentAllowedValueIdentNames := prevAllowedValueIdentNames
                                                                            ));'''
    if old_main_init not in src:
        fail("build-hxhx: failed to locate bootstrap main static-init exprToOcaml anchor for allowed-ident repair\n")
    src = src.replace(old_main_init, new_main_init, 1)

    old_main_after = '''                                                                            let initOcaml = (!tempString47 : string) in (
                                                                              ignore (HxArray.push out ((("let " ^ HxString.toStdString (ocamlValueIdent (nameRaw : string))) ^ " = ") ^ HxString.toStdString initOcaml));
                                                                              if HxMap.get_string staticTyByIdent nameRaw == Obj.magic (HxRuntime.hx_null) then ignore (let value = Obj.magic (TyType.unknown ()) in HxMap.set_string staticTyByIdent nameRaw value) else ()'''
    new_main_after = '''                                                                            let initOcaml = (!tempString47 : string) in (
                                                                              ignore (HxArray.push out ((("let " ^ HxString.toStdString (ocamlValueIdent (nameRaw : string))) ^ " = ") ^ HxString.toStdString initOcaml));
                                                                              ignore (HxMap.set_string staticAllowedValueIdents nameRaw true);
                                                                              if HxMap.get_string staticTyByIdent nameRaw == Obj.magic (HxRuntime.hx_null) then ignore (let value = Obj.magic (TyType.unknown ()) in HxMap.set_string staticTyByIdent nameRaw value) else ()'''
    if old_main_after not in src:
        fail("build-hxhx: failed to locate bootstrap main static-init post-bind anchor for allowed-ident repair\n")
    src = src.replace(old_main_after, new_main_after, 1)

    write_text(path_str, src)


def cmd_patch_stmt_local_allowed_idents(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-stmt-local-allowed-idents <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    helper_old_existing = """let extendAllowedValueIdents = fun base locals -> let out = HxMap.create_string () in let baseKeys = mapKeysRaw (Obj.repr base) in (
                ignore (if baseKeys != Obj.magic (HxRuntime.hx_null) then ignore (let k = baseKeys in while (let __iter_stmt_allowed_1 = k in fun () -> HxIterator.hasNext (Obj.magic __iter_stmt_allowed_1)) () do ignore (let k2 = ((let __iter_stmt_allowed_2 = k in fun () -> HxIterator.next (Obj.magic __iter_stmt_allowed_2)) () : string) in let existing = mapGetRaw (Obj.repr base) (k2 : string) in if existing != Obj.magic (HxRuntime.hx_null) && Obj.obj existing = true then ignore (HxMap.set_string out k2 true) else ()) done) else ());
                let localKeys = mapKeysRaw (Obj.repr locals) in (
                  ignore (if localKeys != Obj.magic (HxRuntime.hx_null) then ignore (let name = localKeys in while (let __iter_stmt_allowed_3 = name in fun () -> HxIterator.hasNext (Obj.magic __iter_stmt_allowed_3)) () do ignore (let name2 = ((let __iter_stmt_allowed_4 = name in fun () -> HxIterator.next (Obj.magic __iter_stmt_allowed_4)) () : string) in if HxMap.get_string locals name2 != Obj.magic (HxRuntime.hx_null) && Obj.obj (Obj.magic (HxMap.get_string locals name2)) = true then ignore (HxMap.set_string out name2 true) else ()) done) else ());
                  out
                )
              )"""
    helper_new_existing = """let extendAllowedValueIdents = fun base locals -> let out = HxMap.create_string () in (
                ignore (if base != Obj.magic (HxRuntime.hx_null) then ignore (let keys = HxMap.keys_string base in let _g_stmt_allowed_1 = ref 0 in while !_g_stmt_allowed_1 < HxArray.length keys do ignore (let k2 = (HxArray.get (Obj.magic keys) (!_g_stmt_allowed_1) : string) in (
                  ignore (let __old_stmt_allowed_1 = !_g_stmt_allowed_1 in let __new_stmt_allowed_1 = HxInt.add __old_stmt_allowed_1 1 in (
                    ignore (_g_stmt_allowed_1 := __new_stmt_allowed_1);
                    __new_stmt_allowed_1
                  ));
                  let __nullable_base = HxMap.get_string base k2 in if __nullable_base != Obj.magic (HxRuntime.hx_null) && Obj.obj __nullable_base = true then ignore (HxMap.set_string out k2 true) else ()
                )) done) else ());
                ignore (if locals != Obj.magic (HxRuntime.hx_null) then ignore (let keys = HxMap.keys_string locals in let _g_stmt_allowed_2 = ref 0 in while !_g_stmt_allowed_2 < HxArray.length keys do ignore (let name2 = (HxArray.get (Obj.magic keys) (!_g_stmt_allowed_2) : string) in (
                  ignore (let __old_stmt_allowed_2 = !_g_stmt_allowed_2 in let __new_stmt_allowed_2 = HxInt.add __old_stmt_allowed_2 1 in (
                    ignore (_g_stmt_allowed_2 := __new_stmt_allowed_2);
                    __new_stmt_allowed_2
                  ));
                  let __nullable_local = HxMap.get_string locals name2 in if __nullable_local != Obj.magic (HxRuntime.hx_null) && Obj.obj __nullable_local = true then ignore (HxMap.set_string out name2 true) else ()
                )) done) else ());
                out
              )"""

    if helper_old_existing in src:
        src = src.replace(helper_old_existing, helper_new_existing, 1)

    if "let extendAllowedValueIdents = fun base locals ->" not in src:
        helper_old = """) in Obj.magic __fallback_result_46042 with
                | HxRuntime.Hx_return __ret_46041 -> Obj.obj __ret_46041 in let extendTyByIdentLocal = fun ty name t -> let out = HxMap.create_string () in let keys = mapKeysRaw (Obj.repr ty) in ("""
        helper_old_typed_copy = """) in Obj.magic __fallback_result_46042 with
                | HxRuntime.Hx_return __ret_46041 -> Obj.obj __ret_46041 in let extendTyByIdentLocal = fun ty name t -> let out = HxMap.create_string () in let typedTy = Obj.magic ty in let keys = if typedTy == Obj.magic (HxRuntime.hx_null) then Obj.magic (HxRuntime.hx_null) else HxMap.keys_string typedTy in ("""
        helper_new = """) in Obj.magic __fallback_result_46042 with
                | HxRuntime.Hx_return __ret_46041 -> Obj.obj __ret_46041 in let extendAllowedValueIdents = fun base locals -> let out = HxMap.create_string () in (
                ignore (if base != Obj.magic (HxRuntime.hx_null) then ignore (let keys = HxMap.keys_string base in let _g_stmt_allowed_1 = ref 0 in while !_g_stmt_allowed_1 < HxArray.length keys do ignore (let k2 = (HxArray.get (Obj.magic keys) (!_g_stmt_allowed_1) : string) in (
                  ignore (let __old_stmt_allowed_1 = !_g_stmt_allowed_1 in let __new_stmt_allowed_1 = HxInt.add __old_stmt_allowed_1 1 in (
                    ignore (_g_stmt_allowed_1 := __new_stmt_allowed_1);
                    __new_stmt_allowed_1
                  ));
                  let __nullable_base = HxMap.get_string base k2 in if __nullable_base != Obj.magic (HxRuntime.hx_null) && Obj.obj __nullable_base = true then ignore (HxMap.set_string out k2 true) else ()
                )) done) else ());
                ignore (if locals != Obj.magic (HxRuntime.hx_null) then ignore (let keys = HxMap.keys_string locals in let _g_stmt_allowed_2 = ref 0 in while !_g_stmt_allowed_2 < HxArray.length keys do ignore (let name2 = (HxArray.get (Obj.magic keys) (!_g_stmt_allowed_2) : string) in (
                  ignore (let __old_stmt_allowed_2 = !_g_stmt_allowed_2 in let __new_stmt_allowed_2 = HxInt.add __old_stmt_allowed_2 1 in (
                    ignore (_g_stmt_allowed_2 := __new_stmt_allowed_2);
                    __new_stmt_allowed_2
                  ));
                  let __nullable_local = HxMap.get_string locals name2 in if __nullable_local != Obj.magic (HxRuntime.hx_null) && Obj.obj __nullable_local = true then ignore (HxMap.set_string out name2 true) else ()
                )) done) else ());
                out
              ) in let extendTyByIdentLocal = fun ty name t -> let out = HxMap.create_string () in let typedTy = Obj.magic ty in let keys = if typedTy == Obj.magic (HxRuntime.hx_null) then Obj.magic (HxRuntime.hx_null) else HxMap.keys_string typedTy in (
                (* hxhx(stage3) bootstrap shim: stmt-local allowed idents repair *)"""
        if helper_old in src:
            src = src.replace(helper_old, helper_new, 1)
        elif helper_old_typed_copy in src:
            src = src.replace(helper_old_typed_copy, helper_new, 1)
        else:
            return

    cond_start = """let condToOcamlBool = fun e tyCtx -> let tempResult2 = ref ("" : string) in ("""
    cond_end = """) in let mutableAssignmentStmtToUnit = fun op name rhs tyCtx -> try let __fallback_result_46078 = ("""
    cond_start_idx = src.find(cond_start)
    cond_end_idx = src.find(cond_end, cond_start_idx)
    if cond_start_idx == -1 or cond_end_idx == -1:
        fail("build-hxhx: failed to locate bootstrap condToOcamlBool chunk for stmt-local allowed repair\n")
    cond_chunk = src[cond_start_idx:cond_end_idx]
    cond_chunk = cond_chunk.replace(
        "let condToOcamlBool = fun e tyCtx ->",
        "let condToOcamlBool = fun e tyCtx allowedValueIdentsForStmt ->",
        1,
    )
    cond_chunk = cond_chunk.replace(
        "returnExprToOcaml (Obj.magic e) allowedValueIdents ",
        "returnExprToOcaml (Obj.magic e) allowedValueIdentsForStmt ",
    )
    src = src[:cond_start_idx] + cond_chunk + src[cond_end_idx:]

    mutable_start = """let mutableAssignmentStmtToUnit = fun op name rhs tyCtx -> try let __fallback_result_46078 = ("""
    mutable_end = """) in Obj.magic __fallback_result_46078 with
                  | HxRuntime.Hx_return __ret_46077 -> Obj.obj __ret_46077 in let bodyHintsIntLoopVar = ref"""
    mutable_start_idx = src.find(mutable_start)
    mutable_end_idx = src.find(mutable_end, mutable_start_idx)
    if mutable_start_idx == -1 or mutable_end_idx == -1:
        fail("build-hxhx: failed to locate bootstrap mutableAssignmentStmtToUnit chunk for stmt-local allowed repair\n")
    mutable_chunk = src[mutable_start_idx:mutable_end_idx]
    mutable_chunk = mutable_chunk.replace(
        "let mutableAssignmentStmtToUnit = fun op name rhs tyCtx ->",
        "let mutableAssignmentStmtToUnit = fun op name rhs tyCtx allowedValueIdentsForStmt ->",
        1,
    )
    mutable_chunk = mutable_chunk.replace(" allowedValueIdents ", " allowedValueIdentsForStmt ")
    src = src[:mutable_start_idx] + mutable_chunk + src[mutable_end_idx:]

    stmt_start = """let stmtToUnit = ref (Obj.magic (HxRuntime.hx_null) : HxStmt.hxstmt -> TyType.t HxMap.string_map -> string) in ("""
    stmt_end = """));
                    let out = ref ("()" : string) in ("""
    stmt_start_idx = src.find(stmt_start)
    stmt_end_idx = src.find(stmt_end, stmt_start_idx)
    if stmt_start_idx == -1 or stmt_end_idx == -1:
        fail("build-hxhx: failed to locate bootstrap stmtToUnit chunk for stmt-local allowed repair\n")
    stmt_chunk = src[stmt_start_idx:stmt_end_idx]
    stmt_chunk = stmt_chunk.replace(
        "let stmtToUnit = ref (Obj.magic (HxRuntime.hx_null) : HxStmt.hxstmt -> TyType.t HxMap.string_map -> string) in (",
        "let stmtToUnit = ref (Obj.magic (HxRuntime.hx_null) : HxStmt.hxstmt -> TyType.t HxMap.string_map -> bool HxMap.string_map -> string) in (",
        1,
    )
    stmt_chunk = stmt_chunk.replace("fun s tyCtx ->", "fun s tyCtx allowedValueIdentsForStmt ->", 1)
    stmt_chunk = stmt_chunk.replace(
        "fun s tyCtx allowedValueIdentsForStmt -> let tempResult6 = ref (\"\" : string) in (",
        "fun s tyCtx allowedValueIdentsForStmt -> let prevAllowedValueIdentNamesStmt = (!currentAllowedValueIdentNames : bool HxMap.string_map) in let _bootstrap_stmt_allowed_assign = let __assign_bootstrap_stmt_allowed_names = Obj.magic allowedValueIdentsForStmt in (\n                      currentAllowedValueIdentNames := __assign_bootstrap_stmt_allowed_names;\n                      __assign_bootstrap_stmt_allowed_names\n                    ) in let tempResult6 = ref (\"\" : string) in (\n                      ignore _bootstrap_stmt_allowed_assign;",
        1,
    )
    stmt_chunk = stmt_chunk.replace("stmtListToOcaml (Obj.magic ss) allowedValueIdents ", "stmtListToOcaml (Obj.magic ss) allowedValueIdentsForStmt ")
    stmt_chunk = stmt_chunk.replace("(!stmtToUnit) (Obj.magic body) caseTy", "(!stmtToUnit) (Obj.magic body) caseTy allowedValueIdentsForStmt")
    stmt_chunk = stmt_chunk.replace("(!stmtToUnit) (Obj.magic body) bodyTy", "(!stmtToUnit) (Obj.magic body) bodyTy allowedValueIdentsForStmt")
    stmt_chunk = stmt_chunk.replace("(!stmtToUnit) (Obj.magic tryBody) tyCtx", "(!stmtToUnit) (Obj.magic tryBody) tyCtx allowedValueIdentsForStmt")
    stmt_chunk = stmt_chunk.replace("(!stmtToUnit) (Obj.magic thenBranch) tyCtx", "(!stmtToUnit) (Obj.magic thenBranch) tyCtx allowedValueIdentsForStmt")
    stmt_chunk = stmt_chunk.replace("(!stmtToUnit) (Obj.obj (HxEnum.unbox_or_obj \"HxStmt\" elseBranch)) tyCtx",
                                    "(!stmtToUnit) (Obj.obj (HxEnum.unbox_or_obj \"HxStmt\" elseBranch)) tyCtx allowedValueIdentsForStmt")
    stmt_chunk = stmt_chunk.replace("(!stmtToUnit) (Obj.magic body) tyCtx", "(!stmtToUnit) (Obj.magic body) tyCtx allowedValueIdentsForStmt")
    stmt_chunk = stmt_chunk.replace("((!stmtToUnit) (Obj.magic s) tyCtx : string)", "((!stmtToUnit) (Obj.magic s) tyCtx allowedValueIdentsForStmt : string)")
    stmt_chunk = stmt_chunk.replace("((!stmtToUnit) (Obj.magic s) tyCtx))", "((!stmtToUnit) (Obj.magic s) tyCtx allowedValueIdentsForStmt))")
    stmt_chunk = stmt_chunk.replace("HxString.toStdString ((!stmtToUnit) (Obj.magic s) tyCtx))",
                                    "HxString.toStdString ((!stmtToUnit) (Obj.magic s) tyCtx allowedValueIdentsForStmt))")
    stmt_chunk = stmt_chunk.replace("condToOcamlBool (Obj.magic cond) tyCtx", "condToOcamlBool (Obj.magic cond) tyCtx allowedValueIdentsForStmt")
    stmt_chunk = stmt_chunk.replace("mutableAssignmentStmtToUnit (op : string) (name : string) (Obj.magic rhs) (Obj.repr tyCtx)",
                                    "mutableAssignmentStmtToUnit (op : string) (name : string) (Obj.magic rhs) (Obj.repr tyCtx) allowedValueIdentsForStmt")
    stmt_chunk = stmt_chunk.replace(" allowedValueIdents ", " allowedValueIdentsForStmt ")
    stmt_chunk = replace_one(
        stmt_chunk,
        """                      !tempResult6
                    ))""",
        """                      let __stmt_result = (!tempResult6 : string) in (
                        ignore (let __assign_bootstrap_restore_stmt_allowed = prevAllowedValueIdentNamesStmt in (
                          currentAllowedValueIdentNames := __assign_bootstrap_restore_stmt_allowed;
                          __assign_bootstrap_restore_stmt_allowed
                        ));
                        __stmt_result
                      )
                    ))""",
        "build-hxhx: failed to locate bootstrap stmtToUnit restore point for stmt-local allowed repair\n",
    )
    src = src[:stmt_start_idx] + stmt_chunk + src[stmt_end_idx:]

    src = replace_one(
        src,
        """let idx = HxInt.sub (HxInt.sub (HxArray.length stmts) 1) i in let s = Obj.magic (HxArray.get (Obj.magic stmts) idx) in let tyCtx = extendTyWithLocals tyByIdent (HxArray.get (Obj.magic localsBefore) idx) in match s with""",
        """let idx = HxInt.sub (HxInt.sub (HxArray.length stmts) 1) i in let s = Obj.magic (HxArray.get (Obj.magic stmts) idx) in let localsForStmt = Obj.magic (HxArray.get (Obj.magic localsBefore) idx) in let tyCtx = extendTyWithLocals tyByIdent (Obj.magic localsForStmt) in let allowedValueIdentsForStmt = extendAllowedValueIdents allowedValueIdents (Obj.magic localsForStmt) in match s with""",
        "build-hxhx: failed to locate bootstrap stmt-fold anchor for stmt-local allowed repair\n",
    )
    src = src.replace("returnExprToOcaml (Obj.obj (HxEnum.unbox_or_obj \"HxExpr\" init)) allowedValueIdents ",
                      "returnExprToOcaml (Obj.obj (HxEnum.unbox_or_obj \"HxExpr\" init)) allowedValueIdentsForStmt ")
    src = src.replace("returnExprToOcaml (Obj.magic (Obj.obj (HxEnum.unbox_or_obj \"HxExpr\" (HxAnon.get assign \"rhs\")))) allowedValueIdents ",
                      "returnExprToOcaml (Obj.magic (Obj.obj (HxEnum.unbox_or_obj \"HxExpr\" (HxAnon.get assign \"rhs\")))) allowedValueIdentsForStmt ")
    src = src.replace("((!stmtToUnit) (Obj.magic s) tyCtx : string)", "((!stmtToUnit) (Obj.magic s) tyCtx allowedValueIdentsForStmt : string)")
    src = src.replace("HxString.toStdString ((!stmtToUnit) (Obj.magic s) tyCtx))",
                      "HxString.toStdString ((!stmtToUnit) (Obj.magic s) tyCtx allowedValueIdentsForStmt))")
    src = src.replace("condToOcamlBool (Obj.magic cond) tyCtx)",
                      "condToOcamlBool (Obj.magic cond) tyCtx allowedValueIdentsForStmt)")

    write_text(path_str, src)


def cmd_patch_typed_ty_map_copying(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-typed-ty-map-copying <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    # Current bootstrap snapshots may already have moved past the legacy
    # mapKeysRaw/mapGetRaw copy helpers this repair targeted.
    if (
        "mapKeysRaw (Obj.repr ty)" not in src
        and "typedMapKeys (Obj.repr ty)" not in src
        and "mapKeysRaw (Obj.repr base)" not in src
        and "mapKeysRaw (Obj.repr locals)" not in src
        and "mapGetRaw (Obj.repr ty)" not in src
        and "typedMapGet (Obj.repr ty)" not in src
        and "mapGetRaw (Obj.repr base)" not in src
        and "mapGetRaw (Obj.repr locals)" not in src
    ):
        return

    src = src.replace(
        """in let extendTyByIdent = fun ty name t -> let out = HxMap.create_string () in let keys = typedMapKeys (Obj.repr ty) in (
                    ignore (if keys != Obj.magic (HxRuntime.hx_null) then ignore (let k = keys in while (let __iter_423 = k in fun () -> HxIterator.hasNext (Obj.magic __iter_423)) () do ignore (let k2 = ((let __iter_424 = k in fun () -> HxIterator.next (Obj.magic __iter_424)) () : string) in let existing = Obj.magic (typedMapGet (Obj.repr ty) (k2 : string)) in if existing != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existing) else ()) done) else ());
                    ignore (HxMap.set_string out name t);
                    out
                  )""",
        """in let extendTyByIdent = fun ty name t -> let out = HxMap.create_string () in let typedTy = Obj.magic ty in let keys = if typedTy == Obj.magic (HxRuntime.hx_null) then Obj.magic (HxRuntime.hx_null) else HxMap.keys_string typedTy in (
                    ignore (if keys != Obj.magic (HxRuntime.hx_null) then ignore (let _g_ty_copy_1 = ref 0 in while !_g_ty_copy_1 < HxArray.length keys do ignore (let k2 = (HxArray.get (Obj.magic keys) (!_g_ty_copy_1) : string) in (
                      ignore (let __old_ty_copy_1 = !_g_ty_copy_1 in let __new_ty_copy_1 = HxInt.add __old_ty_copy_1 1 in (
                        ignore (_g_ty_copy_1 := __new_ty_copy_1);
                        __new_ty_copy_1
                      ));
                      let existing = Obj.magic (HxMap.get_string typedTy k2) in if existing != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existing) else ()
                    )) done) else ());
                    ignore (HxMap.set_string out name t);
                    out
                  )""",
    )

    src = src.replace(
        """in let extendTyByIdentMany = fun ty names t -> let out = HxMap.create_string () in let keys = typedMapKeys (Obj.repr ty) in (
                    ignore (if keys != Obj.magic (HxRuntime.hx_null) then ignore (let k = keys in while (let __iter_425 = k in fun () -> HxIterator.hasNext (Obj.magic __iter_425)) () do ignore (let k2 = ((let __iter_426 = k in fun () -> HxIterator.next (Obj.magic __iter_426)) () : string) in let existing = Obj.magic (typedMapGet (Obj.repr ty) (k2 : string)) in if existing != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existing) else ()) done) else ());
                    ignore (if names != Obj.magic (HxRuntime.hx_null) then ignore (let _g = ref 0 in while !_g < HxArray.length names do ignore (let n = (HxArray.get (Obj.magic names) (!_g) : string) in (
                      ignore (let __old_427 = !_g in let __new_428 = HxInt.add __old_427 1 in (
                        ignore (_g := __new_428);
                        __new_428
                      ));
                      HxMap.set_string out n t
                    )) done) else ());
                    out
                  )""",
        """in let extendTyByIdentMany = fun ty names t -> let out = HxMap.create_string () in let typedTy = Obj.magic ty in let keys = if typedTy == Obj.magic (HxRuntime.hx_null) then Obj.magic (HxRuntime.hx_null) else HxMap.keys_string typedTy in (
                    ignore (if keys != Obj.magic (HxRuntime.hx_null) then ignore (let _g_ty_copy_2 = ref 0 in while !_g_ty_copy_2 < HxArray.length keys do ignore (let k2 = (HxArray.get (Obj.magic keys) (!_g_ty_copy_2) : string) in (
                      ignore (let __old_ty_copy_2 = !_g_ty_copy_2 in let __new_ty_copy_2 = HxInt.add __old_ty_copy_2 1 in (
                        ignore (_g_ty_copy_2 := __new_ty_copy_2);
                        __new_ty_copy_2
                      ));
                      let existing = Obj.magic (HxMap.get_string typedTy k2) in if existing != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existing) else ()
                    )) done) else ());
                    ignore (if names != Obj.magic (HxRuntime.hx_null) then ignore (let _g = ref 0 in while !_g < HxArray.length names do ignore (let n = (HxArray.get (Obj.magic names) (!_g) : string) in (
                      ignore (let __old_427 = !_g in let __new_428 = HxInt.add __old_427 1 in (
                        ignore (_g := __new_428);
                        __new_428
                      ));
                      HxMap.set_string out n t
                    )) done) else ());
                    out
                  )""",
    )

    if """in let extendTyByIdent = fun ty name t -> let out = HxMap.create_string () in let keys = mapKeysRaw (Obj.repr ty) in (
                    ignore (if keys != Obj.magic (HxRuntime.hx_null) then ignore (let k = keys in while (let __iter_352 = k in fun () -> HxIterator.hasNext (Obj.magic __iter_352)) () do ignore (let k2 = ((let __iter_353 = k in fun () -> HxIterator.next (Obj.magic __iter_353)) () : string) in let existing = mapGetRaw (Obj.repr ty) (k2 : string) in if existing != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existing) else ()) done) else ());
                    ignore (HxMap.set_string out name t);
                    out
                  )""" in src:
        src = replace_one(
            src,
            """in let extendTyByIdent = fun ty name t -> let out = HxMap.create_string () in let keys = mapKeysRaw (Obj.repr ty) in (
                    ignore (if keys != Obj.magic (HxRuntime.hx_null) then ignore (let k = keys in while (let __iter_352 = k in fun () -> HxIterator.hasNext (Obj.magic __iter_352)) () do ignore (let k2 = ((let __iter_353 = k in fun () -> HxIterator.next (Obj.magic __iter_353)) () : string) in let existing = mapGetRaw (Obj.repr ty) (k2 : string) in if existing != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existing) else ()) done) else ());
                    ignore (HxMap.set_string out name t);
                    out
                  )""",
            """in let extendTyByIdent = fun ty name t -> let out = HxMap.create_string () in let typedTy = Obj.magic ty in let keys = if typedTy == Obj.magic (HxRuntime.hx_null) then Obj.magic (HxRuntime.hx_null) else HxMap.keys_string typedTy in (
                    ignore (if keys != Obj.magic (HxRuntime.hx_null) then ignore (let _g_ty_copy_1 = ref 0 in while !_g_ty_copy_1 < HxArray.length keys do ignore (let k2 = (HxArray.get (Obj.magic keys) (!_g_ty_copy_1) : string) in (
                      ignore (let __old_ty_copy_1 = !_g_ty_copy_1 in let __new_ty_copy_1 = HxInt.add __old_ty_copy_1 1 in (
                        ignore (_g_ty_copy_1 := __new_ty_copy_1);
                        __new_ty_copy_1
                      ));
                      let existing = Obj.magic (HxMap.get_string typedTy k2) in if existing != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existing) else ()
                    )) done) else ());
                    ignore (HxMap.set_string out name t);
                    out
                  )""",
            "build-hxhx: failed to locate bootstrap extendTyByIdent copy anchor in EmitterStage.ml\n",
        )

    if """in let extendTyByIdentMany = fun ty names t -> let out = HxMap.create_string () in let keys = mapKeysRaw (Obj.repr ty) in (
                    ignore (if keys != Obj.magic (HxRuntime.hx_null) then ignore (let k = keys in while (let __iter_354 = k in fun () -> HxIterator.hasNext (Obj.magic __iter_354)) () do ignore (let k2 = ((let __iter_355 = k in fun () -> HxIterator.next (Obj.magic __iter_355)) () : string) in let existing = mapGetRaw (Obj.repr ty) (k2 : string) in if existing != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existing) else ()) done) else ());
                    ignore (if names != Obj.magic (HxRuntime.hx_null) then ignore (let _g = ref 0 in while !_g < HxArray.length names do ignore (let n = (HxArray.get (Obj.magic names) (!_g) : string) in (
                      ignore (let __old_356 = !_g in let __new_357 = HxInt.add __old_356 1 in (
                        ignore (_g := __new_357);
                        __new_357
                      ));
                      HxMap.set_string out n t
                    )) done) else ());
                    out
                  )""" in src:
        src = replace_one(
            src,
            """in let extendTyByIdentMany = fun ty names t -> let out = HxMap.create_string () in let keys = mapKeysRaw (Obj.repr ty) in (
                    ignore (if keys != Obj.magic (HxRuntime.hx_null) then ignore (let k = keys in while (let __iter_354 = k in fun () -> HxIterator.hasNext (Obj.magic __iter_354)) () do ignore (let k2 = ((let __iter_355 = k in fun () -> HxIterator.next (Obj.magic __iter_355)) () : string) in let existing = mapGetRaw (Obj.repr ty) (k2 : string) in if existing != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existing) else ()) done) else ());
                    ignore (if names != Obj.magic (HxRuntime.hx_null) then ignore (let _g = ref 0 in while !_g < HxArray.length names do ignore (let n = (HxArray.get (Obj.magic names) (!_g) : string) in (
                      ignore (let __old_356 = !_g in let __new_357 = HxInt.add __old_356 1 in (
                        ignore (_g := __new_357);
                        __new_357
                      ));
                      HxMap.set_string out n t
                    )) done) else ());
                    out
                  )""",
            """in let extendTyByIdentMany = fun ty names t -> let out = HxMap.create_string () in let typedTy = Obj.magic ty in let keys = if typedTy == Obj.magic (HxRuntime.hx_null) then Obj.magic (HxRuntime.hx_null) else HxMap.keys_string typedTy in (
                    ignore (if keys != Obj.magic (HxRuntime.hx_null) then ignore (let _g_ty_copy_2 = ref 0 in while !_g_ty_copy_2 < HxArray.length keys do ignore (let k2 = (HxArray.get (Obj.magic keys) (!_g_ty_copy_2) : string) in (
                      ignore (let __old_ty_copy_2 = !_g_ty_copy_2 in let __new_ty_copy_2 = HxInt.add __old_ty_copy_2 1 in (
                        ignore (_g_ty_copy_2 := __new_ty_copy_2);
                        __new_ty_copy_2
                      ));
                      let existing = Obj.magic (HxMap.get_string typedTy k2) in if existing != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existing) else ()
                    )) done) else ());
                    ignore (if names != Obj.magic (HxRuntime.hx_null) then ignore (let _g = ref 0 in while !_g < HxArray.length names do ignore (let n = (HxArray.get (Obj.magic names) (!_g) : string) in (
                      ignore (let __old_356 = !_g in let __new_357 = HxInt.add __old_356 1 in (
                        ignore (_g := __new_357);
                        __new_357
                      ));
                      HxMap.set_string out n t
                    )) done) else ());
                    out
                  )""",
            "build-hxhx: failed to locate bootstrap extendTyByIdentMany copy anchor in EmitterStage.ml\n",
        )

    if """in let extendTyWithLocals = fun base locals -> try let __fallback_result_46042 = let out = HxMap.create_string () in let baseKeys = mapKeysRaw (Obj.repr base) in (
                ignore (if baseKeys != Obj.magic (HxRuntime.hx_null) then ignore (let k = baseKeys in while (let __iter_46033 = k in fun () -> HxIterator.hasNext (Obj.magic __iter_46033)) () do ignore (let k2 = ((let __iter_46034 = k in fun () -> HxIterator.next (Obj.magic __iter_46034)) () : string) in let existingBase = mapGetRaw (Obj.repr base) (k2 : string) in if existingBase != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existingBase) else ()) done) else ());
                let localNames = Obj.magic (HxArray.create ()) in let localKeys = mapKeysRaw (Obj.repr locals) in (
                  ignore (if localKeys != Obj.magic (HxRuntime.hx_null) then ignore (let name = localKeys in while (let __iter_46035 = name in fun () -> HxIterator.hasNext (Obj.magic __iter_46035)) () do ignore (let name2 = ((let __iter_46036 = name in fun () -> HxIterator.next (Obj.magic __iter_46036)) () : string) in HxArray.push localNames name2) done) else ());
                  ignore (if HxArray.length localNames = 0 then raise (HxRuntime.Hx_return (Obj.repr out)) else ());
                  ignore (let _g = ref 0 in while !_g < HxArray.length localNames do ignore (let name = (HxArray.get (Obj.magic localNames) (!_g) : string) in (
                    ignore (let __old_46037 = !_g in let __new_46038 = HxInt.add __old_46037 1 in (
                      ignore (_g := __new_46038);
                      __new_46038
                    ));
                    let hinted = Obj.magic (HxMap.get_string localHints name) in let existing = Obj.magic (HxMap.get_string out name) in if existing == Obj.magic (HxRuntime.hx_null) then ignore (let tempTyType2 = ref (Obj.magic (HxRuntime.hx_null) : TyType.t) in (
                      ignore (if hinted != Obj.magic (HxRuntime.hx_null) then let __assign_46039 = Obj.magic hinted in (
                        tempTyType2 := __assign_46039;
                        __assign_46039
                      ) else let __assign_46040 = Obj.magic (TyType.unknown ()) in (
                        tempTyType2 := __assign_46040;
                        __assign_46040
                      ));
                      let value = Obj.magic (!tempTyType2) in HxMap.set_string out name value
                    )) else ignore (if hinted != Obj.magic (HxRuntime.hx_null) then ignore (let existingBroad = TyType.isUnknown (Obj.magic existing) () || HxString.equals (TyType.toString (Obj.magic existing) ()) "Dynamic" || HxString.equals (TyType.toString (Obj.magic existing) ()) "Array" in let hintedUseful = not (TyType.isUnknown (Obj.magic hinted) ()) && not (HxString.equals (TyType.toString (Obj.magic hinted) ()) "Dynamic") in if existingBroad && hintedUseful then ignore (HxMap.set_string out name hinted) else ()) else ())
                  )) done);
                  out
                )
              )""" in src:
        src = replace_one(
            src,
            """in let extendTyWithLocals = fun base locals -> try let __fallback_result_46042 = let out = HxMap.create_string () in let baseKeys = mapKeysRaw (Obj.repr base) in (
                ignore (if baseKeys != Obj.magic (HxRuntime.hx_null) then ignore (let k = baseKeys in while (let __iter_46033 = k in fun () -> HxIterator.hasNext (Obj.magic __iter_46033)) () do ignore (let k2 = ((let __iter_46034 = k in fun () -> HxIterator.next (Obj.magic __iter_46034)) () : string) in let existingBase = mapGetRaw (Obj.repr base) (k2 : string) in if existingBase != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existingBase) else ()) done) else ());
                let localNames = Obj.magic (HxArray.create ()) in let localKeys = mapKeysRaw (Obj.repr locals) in (
                  ignore (if localKeys != Obj.magic (HxRuntime.hx_null) then ignore (let name = localKeys in while (let __iter_46035 = name in fun () -> HxIterator.hasNext (Obj.magic __iter_46035)) () do ignore (let name2 = ((let __iter_46036 = name in fun () -> HxIterator.next (Obj.magic __iter_46036)) () : string) in HxArray.push localNames name2) done) else ());
                  ignore (if HxArray.length localNames = 0 then raise (HxRuntime.Hx_return (Obj.repr out)) else ());
                  ignore (let _g = ref 0 in while !_g < HxArray.length localNames do ignore (let name = (HxArray.get (Obj.magic localNames) (!_g) : string) in (
                    ignore (let __old_46037 = !_g in let __new_46038 = HxInt.add __old_46037 1 in (
                      ignore (_g := __new_46038);
                      __new_46038
                    ));
                    let hinted = Obj.magic (HxMap.get_string localHints name) in let existing = Obj.magic (HxMap.get_string out name) in if existing == Obj.magic (HxRuntime.hx_null) then ignore (let tempTyType2 = ref (Obj.magic (HxRuntime.hx_null) : TyType.t) in (
                      ignore (if hinted != Obj.magic (HxRuntime.hx_null) then let __assign_46039 = Obj.magic hinted in (
                        tempTyType2 := __assign_46039;
                        __assign_46039
                      ) else let __assign_46040 = Obj.magic (TyType.unknown ()) in (
                        tempTyType2 := __assign_46040;
                        __assign_46040
                      ));
                      let value = Obj.magic (!tempTyType2) in HxMap.set_string out name value
                    )) else ignore (if hinted != Obj.magic (HxRuntime.hx_null) then ignore (let existingBroad = TyType.isUnknown (Obj.magic existing) () || HxString.equals (TyType.toString (Obj.magic existing) ()) "Dynamic" || HxString.equals (TyType.toString (Obj.magic existing) ()) "Array" in let hintedUseful = not (TyType.isUnknown (Obj.magic hinted) ()) && not (HxString.equals (TyType.toString (Obj.magic hinted) ()) "Dynamic") in if existingBroad && hintedUseful then ignore (HxMap.set_string out name hinted) else ()) else ())
                  )) done);
                  out
                )
              )""",
            """in let extendTyWithLocals = fun base locals -> try let __fallback_result_46042 = let out = HxMap.create_string () in let typedBase = Obj.magic base in let baseKeys = if typedBase == Obj.magic (HxRuntime.hx_null) then Obj.magic (HxRuntime.hx_null) else HxMap.keys_string typedBase in (
                ignore (if baseKeys != Obj.magic (HxRuntime.hx_null) then ignore (let _g_ty_copy_3 = ref 0 in while !_g_ty_copy_3 < HxArray.length baseKeys do ignore (let k2 = (HxArray.get (Obj.magic baseKeys) (!_g_ty_copy_3) : string) in (
                  ignore (let __old_ty_copy_3 = !_g_ty_copy_3 in let __new_ty_copy_3 = HxInt.add __old_ty_copy_3 1 in (
                    ignore (_g_ty_copy_3 := __new_ty_copy_3);
                    __new_ty_copy_3
                  ));
                  let existingBase = Obj.magic (HxMap.get_string typedBase k2) in if existingBase != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existingBase) else ()
                )) done) else ());
                let localNames = Obj.magic (HxArray.create ()) in let typedLocals = Obj.magic locals in let localKeys = if typedLocals == Obj.magic (HxRuntime.hx_null) then Obj.magic (HxRuntime.hx_null) else HxMap.keys_string typedLocals in (
                  ignore (if localKeys != Obj.magic (HxRuntime.hx_null) then ignore (let _g_ty_copy_4 = ref 0 in while !_g_ty_copy_4 < HxArray.length localKeys do ignore (let name2 = (HxArray.get (Obj.magic localKeys) (!_g_ty_copy_4) : string) in (
                    ignore (let __old_ty_copy_4 = !_g_ty_copy_4 in let __new_ty_copy_4 = HxInt.add __old_ty_copy_4 1 in (
                      ignore (_g_ty_copy_4 := __new_ty_copy_4);
                      __new_ty_copy_4
                    ));
                    HxArray.push localNames name2
                  )) done) else ());
                  ignore (if HxArray.length localNames = 0 then raise (HxRuntime.Hx_return (Obj.repr out)) else ());
                  ignore (let _g = ref 0 in while !_g < HxArray.length localNames do ignore (let name = (HxArray.get (Obj.magic localNames) (!_g) : string) in (
                    ignore (let __old_46037 = !_g in let __new_46038 = HxInt.add __old_46037 1 in (
                      ignore (_g := __new_46038);
                      __new_46038
                    ));
                    let hinted = Obj.magic (HxMap.get_string localHints name) in let existing = Obj.magic (HxMap.get_string out name) in if existing == Obj.magic (HxRuntime.hx_null) then ignore (let tempTyType2 = ref (Obj.magic (HxRuntime.hx_null) : TyType.t) in (
                      ignore (if hinted != Obj.magic (HxRuntime.hx_null) then let __assign_46039 = Obj.magic hinted in (
                        tempTyType2 := __assign_46039;
                        __assign_46039
                      ) else let __assign_46040 = Obj.magic (TyType.unknown ()) in (
                        tempTyType2 := __assign_46040;
                        __assign_46040
                      ));
                      let value = Obj.magic (!tempTyType2) in HxMap.set_string out name value
                    )) else ignore (if hinted != Obj.magic (HxRuntime.hx_null) then ignore (let existingBroad = TyType.isUnknown (Obj.magic existing) () || HxString.equals (TyType.toString (Obj.magic existing) ()) "Dynamic" || HxString.equals (TyType.toString (Obj.magic existing) ()) "Array" in let hintedInt64 = HxString.equals (TyType.toString (Obj.magic hinted) ()) "Int64" || HxString.equals (TyType.toString (Obj.magic hinted) ()) "haxe.Int64" in let existingInt64 = HxString.equals (TyType.toString (Obj.magic existing) ()) "Int64" || HxString.equals (TyType.toString (Obj.magic existing) ()) "haxe.Int64" in let hintedUseful = not (TyType.isUnknown (Obj.magic hinted) ()) && not (HxString.equals (TyType.toString (Obj.magic hinted) ()) "Dynamic") in if (existingBroad || (hintedInt64 && not existingInt64)) && hintedUseful then ignore (HxMap.set_string out name hinted) else ()) else ())
                  )) done);
                  out
                )
              )""",
            "build-hxhx: failed to locate bootstrap extendTyWithLocals copy anchor in EmitterStage.ml\n",
        )

    if """in let extendTyByIdentLocal = fun ty name t -> let out = HxMap.create_string () in let keys = mapKeysRaw (Obj.repr ty) in (
                ignore (if keys != Obj.magic (HxRuntime.hx_null) then ignore (let k = keys in while (let __iter_46043 = k in fun () -> HxIterator.hasNext (Obj.magic __iter_46043)) () do ignore (let k2 = ((let __iter_46044 = k in fun () -> HxIterator.next (Obj.magic __iter_46044)) () : string) in let existing = mapGetRaw (Obj.repr ty) (k2 : string) in if existing != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existing) else ()) done) else ());
                ignore (HxMap.set_string out name t);
                out
              )""" in src:
        src = replace_one(
            src,
            """in let extendTyByIdentLocal = fun ty name t -> let out = HxMap.create_string () in let keys = mapKeysRaw (Obj.repr ty) in (
                ignore (if keys != Obj.magic (HxRuntime.hx_null) then ignore (let k = keys in while (let __iter_46043 = k in fun () -> HxIterator.hasNext (Obj.magic __iter_46043)) () do ignore (let k2 = ((let __iter_46044 = k in fun () -> HxIterator.next (Obj.magic __iter_46044)) () : string) in let existing = mapGetRaw (Obj.repr ty) (k2 : string) in if existing != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existing) else ()) done) else ());
                ignore (HxMap.set_string out name t);
                out
              )""",
            """in let extendTyByIdentLocal = fun ty name t -> let out = HxMap.create_string () in let typedTy = Obj.magic ty in let keys = if typedTy == Obj.magic (HxRuntime.hx_null) then Obj.magic (HxRuntime.hx_null) else HxMap.keys_string typedTy in (
                ignore (if keys != Obj.magic (HxRuntime.hx_null) then ignore (let _g_ty_copy_5 = ref 0 in while !_g_ty_copy_5 < HxArray.length keys do ignore (let k2 = (HxArray.get (Obj.magic keys) (!_g_ty_copy_5) : string) in (
                  ignore (let __old_ty_copy_5 = !_g_ty_copy_5 in let __new_ty_copy_5 = HxInt.add __old_ty_copy_5 1 in (
                    ignore (_g_ty_copy_5 := __new_ty_copy_5);
                    __new_ty_copy_5
                  ));
                  let existing = Obj.magic (HxMap.get_string typedTy k2) in if existing != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existing) else ()
                )) done) else ());
                ignore (HxMap.set_string out name t);
                out
              )""",
            "build-hxhx: failed to locate bootstrap extendTyByIdentLocal copy anchor in EmitterStage.ml\n",
        )

    if """in let cloneTyCtxLocal = fun ty -> let out = HxMap.create_string () in let keys = mapKeysRaw (Obj.repr ty) in (
                ignore (if keys != Obj.magic (HxRuntime.hx_null) then ignore (let k = keys in while (let __iter_46045 = k in fun () -> HxIterator.hasNext (Obj.magic __iter_46045)) () do ignore (let k2 = ((let __iter_46046 = k in fun () -> HxIterator.next (Obj.magic __iter_46046)) () : string) in let existing = mapGetRaw (Obj.repr ty) (k2 : string) in if existing != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existing) else ()) done) else ());
                out
              )""" in src:
        src = replace_one(
            src,
            """in let cloneTyCtxLocal = fun ty -> let out = HxMap.create_string () in let keys = mapKeysRaw (Obj.repr ty) in (
                ignore (if keys != Obj.magic (HxRuntime.hx_null) then ignore (let k = keys in while (let __iter_46045 = k in fun () -> HxIterator.hasNext (Obj.magic __iter_46045)) () do ignore (let k2 = ((let __iter_46046 = k in fun () -> HxIterator.next (Obj.magic __iter_46046)) () : string) in let existing = mapGetRaw (Obj.repr ty) (k2 : string) in if existing != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existing) else ()) done) else ());
                out
              )""",
            """in let cloneTyCtxLocal = fun ty -> let out = HxMap.create_string () in let typedTy = Obj.magic ty in let keys = if typedTy == Obj.magic (HxRuntime.hx_null) then Obj.magic (HxRuntime.hx_null) else HxMap.keys_string typedTy in (
                ignore (if keys != Obj.magic (HxRuntime.hx_null) then ignore (let _g_ty_copy_6 = ref 0 in while !_g_ty_copy_6 < HxArray.length keys do ignore (let k2 = (HxArray.get (Obj.magic keys) (!_g_ty_copy_6) : string) in (
                  ignore (let __old_ty_copy_6 = !_g_ty_copy_6 in let __new_ty_copy_6 = HxInt.add __old_ty_copy_6 1 in (
                    ignore (_g_ty_copy_6 := __new_ty_copy_6);
                    __new_ty_copy_6
                  ));
                  let existing = Obj.magic (HxMap.get_string typedTy k2) in if existing != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existing) else ()
                )) done) else ());
                out
              )""",
            "build-hxhx: failed to locate bootstrap cloneTyCtxLocal copy anchor in EmitterStage.ml\n",
        )

    src = src.replace(
        """in let extendTyByIdentLocal = fun ty name t -> let out = HxMap.create_string () in let keys = typedMapKeys (Obj.repr ty) in (
                ignore (if keys != Obj.magic (HxRuntime.hx_null) then ignore (let k = keys in while (let __iter_51004 = k in fun () -> HxIterator.hasNext (Obj.magic __iter_51004)) () do ignore (let k2 = ((let __iter_51005 = k in fun () -> HxIterator.next (Obj.magic __iter_51005)) () : string) in let existing = Obj.magic (typedMapGet (Obj.repr ty) (k2 : string)) in if existing != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existing) else ()) done) else ());
                ignore (HxMap.set_string out name t);
                out
              )""",
        """in let extendTyByIdentLocal = fun ty name t -> let out = HxMap.create_string () in let typedTy = Obj.magic ty in let keys = if typedTy == Obj.magic (HxRuntime.hx_null) then Obj.magic (HxRuntime.hx_null) else HxMap.keys_string typedTy in (
                ignore (if keys != Obj.magic (HxRuntime.hx_null) then ignore (let _g_ty_copy_5 = ref 0 in while !_g_ty_copy_5 < HxArray.length keys do ignore (let k2 = (HxArray.get (Obj.magic keys) (!_g_ty_copy_5) : string) in (
                  ignore (let __old_ty_copy_5 = !_g_ty_copy_5 in let __new_ty_copy_5 = HxInt.add __old_ty_copy_5 1 in (
                    ignore (_g_ty_copy_5 := __new_ty_copy_5);
                    __new_ty_copy_5
                  ));
                  let existing = Obj.magic (HxMap.get_string typedTy k2) in if existing != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existing) else ()
                )) done) else ());
                ignore (HxMap.set_string out name t);
                out
              )""",
    )

    src = src.replace(
        """in let cloneTyCtxLocal = fun ty -> let out = HxMap.create_string () in let keys = typedMapKeys (Obj.repr ty) in (
                ignore (if keys != Obj.magic (HxRuntime.hx_null) then ignore (let k = keys in while (let __iter_51006 = k in fun () -> HxIterator.hasNext (Obj.magic __iter_51006)) () do ignore (let k2 = ((let __iter_51007 = k in fun () -> HxIterator.next (Obj.magic __iter_51007)) () : string) in let existing = Obj.magic (typedMapGet (Obj.repr ty) (k2 : string)) in if existing != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existing) else ()) done) else ());
                out
              )""",
        """in let cloneTyCtxLocal = fun ty -> let out = HxMap.create_string () in let typedTy = Obj.magic ty in let keys = if typedTy == Obj.magic (HxRuntime.hx_null) then Obj.magic (HxRuntime.hx_null) else HxMap.keys_string typedTy in (
                ignore (if keys != Obj.magic (HxRuntime.hx_null) then ignore (let _g_ty_copy_6 = ref 0 in while !_g_ty_copy_6 < HxArray.length keys do ignore (let k2 = (HxArray.get (Obj.magic keys) (!_g_ty_copy_6) : string) in (
                  ignore (let __old_ty_copy_6 = !_g_ty_copy_6 in let __new_ty_copy_6 = HxInt.add __old_ty_copy_6 1 in (
                    ignore (_g_ty_copy_6 := __new_ty_copy_6);
                    __new_ty_copy_6
                  ));
                  let existing = Obj.magic (HxMap.get_string typedTy k2) in if existing != Obj.magic (HxRuntime.hx_null) then ignore (HxMap.set_string out k2 existing) else ()
                )) done) else ());
                out
              )""",
    )

    write_text(path_str, src)


def cmd_patch_typed_map_helper_obj_repr(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-typed-map-helper-obj-repr <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    replacements = [
        ("typedMapGet (Obj.repr tyByIdent)", "typedMapGet (Obj.magic tyByIdent)"),
        ("typedMapHas (Obj.repr tyByIdent)", "typedMapHas (Obj.magic tyByIdent)"),
        ("typedMapGet (Obj.repr arityByIdent)", "typedMapGet (Obj.magic arityByIdent)"),
        ("typedMapHas (Obj.repr arityByIdent)", "typedMapHas (Obj.magic arityByIdent)"),
        ("typedMapGet (Obj.repr staticImportByIdent)", "typedMapGet (Obj.magic staticImportByIdent)"),
        ("typedMapHas (Obj.repr staticImportByIdent)", "typedMapHas (Obj.magic staticImportByIdent)"),
        ("typedMapGet (Obj.repr moduleNameByPkgAndClass)", "typedMapGet (Obj.magic moduleNameByPkgAndClass)"),
        ("typedMapHas (Obj.repr moduleNameByPkgAndClass)", "typedMapHas (Obj.magic moduleNameByPkgAndClass)"),
        ("typedMapGet (Obj.repr callSigByCallee)", "typedMapGet (Obj.magic callSigByCallee)"),
        ("typedMapHas (Obj.repr callSigByCallee)", "typedMapHas (Obj.magic callSigByCallee)"),
        ("typedMapGet (Obj.repr (!currentGlobalImportAliasByIdent))", "typedMapGet (Obj.magic (!currentGlobalImportAliasByIdent))"),
        ("typedMapHas (Obj.repr (!currentGlobalImportAliasByIdent))", "typedMapHas (Obj.magic (!currentGlobalImportAliasByIdent))"),
    ]

    if not any(old in src for old, _new in replacements):
        pass

    changed = False
    for old, new in replacements:
        if old in src:
            src = src.replace(old, new)
            changed = True

    src2 = re.sub(
        r"\b(?P<fn>typedMapKeys|typedMapGet|typedMapHas) \(Obj\.repr (?P<var>[A-Za-z_!][A-Za-z0-9_]*)\)",
        r"\g<fn> (Obj.magic \g<var>)",
        src,
    )
    changed = changed or src2 != src
    src = src2

    if not changed:
        # Newer regenerated snapshots may already avoid these helper call shapes.
        # In that case this repair is simply unnecessary and bootstrap should continue.
        return

    write_text(path_str, src + "\n(* hxhx(stage3) bootstrap shim: typed-map Obj.repr helper repair *)\n")


def cmd_patch_fast_emitter_nested_literals(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-fast-emitter-nested-literals <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    changed = False
    old = "exprToOcamlString (Obj.magic expr) (Obj.repr tyByIdent) (Obj.repr arityByIdent) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee)"
    new = "exprToOcamlString (Obj.magic expr) (Obj.magic tyByIdent) (Obj.magic arityByIdent) (Obj.magic staticImportByIdent) (currentPackagePath : string) (Obj.magic moduleNameByPkgAndClass) (Obj.magic callSigByCallee)"
    if old in src:
        src = src.replace(old, new)
        changed = True

    if not changed:
        return

    write_text(path_str, src + "\n(* hxhx(stage3) bootstrap shim: fast nested literal repair *)\n")


def cmd_patch_nested_emitter_call_arg_reprs(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-nested-emitter-call-arg-reprs <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    stale_nested_call_families = (
        lambda s: "exprToOcamlString (Obj.magic " in s
        and " (Obj.repr tyByIdent) (Obj.repr arityByIdent) " in s,
        lambda s: "exprToOcaml (Obj.magic " in s
        and (
            " (Obj.repr arityByIdent) (Obj.repr tyByIdent) (Obj.repr staticImportByIdent) " in s
            or " (Obj.repr arityByName) (Obj.repr staticTyByIdent) (Obj.repr staticImportByIdent) " in s
            or " (Obj.repr arityByName) tyByIdent staticImportByIdent " in s
            or " arityByIdent tyCtx staticImportByIdent " in s
        ),
        lambda s: "stmtListToOcaml (Obj.magic " in s
        and (
            " (Obj.repr arityByIdent) (Obj.repr tyCtx) " in s
            or " arityByIdent tyCtx " in s
        ),
        lambda s: "mutableAssignmentStmtToUnit " in s
        and " (Obj.repr tyCtx)" in s,
        lambda s: "returnExprToOcaml (Obj.magic " in s
        and (
            " (Obj.repr arityByIdent) " in s
            or " (Obj.repr arityByName) " in s
            or " arityByIdent tyCtx staticImportByIdent " in s
        ),
        lambda s: "returnExprToOcaml (Obj.obj " in s
        and (
            " (Obj.repr arityByIdent) " in s
            or " (Obj.repr arityByName) " in s
        ),
        lambda s: "extendTyByIdentMany (Obj.repr " in s,
    )

    if not any(predicate(src) for predicate in stale_nested_call_families):
        return

    changed = False

    src2 = src.replace(
        "exprToOcamlString (Obj.magic expr) (Obj.repr tyByIdent) (Obj.repr arityByIdent) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee)",
        "exprToOcamlString (Obj.magic expr) tyByIdent arityByIdent staticImportByIdent (currentPackagePath : string) moduleNameByPkgAndClass callSigByCallee",
    )
    changed = changed or src2 != src
    src = src2

    src2 = re.sub(
        r"exprToOcamlString \(Obj\.magic (?P<expr>.*?)\) \(Obj\.repr tyByIdent\) \(Obj\.repr arityByIdent\) \(Obj\.repr staticImportByIdent\) \(currentPackagePath : string\) \(Obj\.repr moduleNameByPkgAndClass\) \(Obj\.repr callSigByCallee\)",
        r"exprToOcamlString (Obj.magic \g<expr>) tyByIdent arityByIdent staticImportByIdent (currentPackagePath : string) moduleNameByPkgAndClass callSigByCallee",
        src,
        flags=re.S,
    )
    changed = changed or src2 != src
    src = src2

    def _expr_to_ocaml_static_repl(match: re.Match[str]) -> str:
        return (
            f"exprToOcaml (Obj.{match.group('wrap')} {match.group('expr')}) "
            "(HxMap.create_string ()) "
            f"{match.group('ty')} "
            "(HxMap.create_string ()) "
            f"{match.group('path')} "
            "moduleNameByPkgAndClass "
            f"{match.group('call')}"
        )

    src2 = re.sub(
        r"exprToOcaml \(Obj\.(?P<wrap>magic|obj) (?P<expr>.*?)\) "
        r"\(HxRuntime\.hx_null\) "
        r"\(Obj\.repr (?P<ty>[A-Za-z_!][A-Za-z0-9_]*)\) "
        r"\(HxRuntime\.hx_null\) "
        r"(?P<path>\(HxModuleDecl\.getPackagePath .*?\) : string\)) "
        r"\(Obj\.repr moduleNameByPkgAndClass\) "
        r"\(Obj\.repr (?P<call>[A-Za-z_!][A-Za-z0-9_]*)\)",
        _expr_to_ocaml_static_repl,
        src,
        flags=re.S,
    )
    changed = changed or src2 != src
    src = src2

    def _expr_to_ocaml_repl(match: re.Match[str]) -> str:
        last = match.group("last")
        if last == "Obj.repr callSigByCallee":
            last = "callSigByCallee"
        return (
            f"exprToOcaml (Obj.magic {match.group('expr')}) "
            "arityByIdent tyByIdent staticImportByIdent "
            "(currentPackagePath : string) moduleNameByPkgAndClass "
            f"({last})"
        )

    src2 = re.sub(
        r"exprToOcaml \(Obj\.magic (?P<expr>.*?)\) \(Obj\.repr arityByIdent\) \(Obj\.repr tyByIdent\) \(Obj\.repr staticImportByIdent\) \(currentPackagePath : string\) \(Obj\.repr moduleNameByPkgAndClass\) \((?P<last>Obj\.repr callSigByCallee|Obj\.magic \(HxRuntime\.hx_null\))\)",
        _expr_to_ocaml_repl,
        src,
        flags=re.S,
    )
    changed = changed or src2 != src
    src = src2

    def _normalize_repaired_arg(raw: str) -> str:
        raw = raw.strip()
        if raw.startswith("(Obj.repr ") and raw.endswith(")"):
            return raw[len("(Obj.repr ") : -1]
        if re.fullmatch(r"\([A-Za-z_!][A-Za-z0-9_]*\)", raw):
            return raw[1:-1]
        return raw

    def _expr_to_ocaml_any_local_ty_repl(match: re.Match[str]) -> str:
        return (
            f"exprToOcaml (Obj.{match.group('wrap')} {match.group('expr')}) "
            f"{_normalize_repaired_arg(match.group('arity'))} "
            f"{_normalize_repaired_arg(match.group('ty'))} "
            f"{_normalize_repaired_arg(match.group('static_import'))} "
            f"{match.group('path')} {_normalize_repaired_arg(match.group('module_map'))} "
            f"{_normalize_repaired_arg(match.group('call_map'))}"
        )

    src2 = re.sub(
        r"exprToOcaml \(Obj\.(?P<wrap>magic|obj) (?P<expr>.*?)\) "
        r"(?P<arity>\(Obj\.repr [A-Za-z_!][A-Za-z0-9_]*\)|[A-Za-z_!][A-Za-z0-9_]*) "
        r"(?P<ty>\(Obj\.repr [A-Za-z_!][A-Za-z0-9_]*\)|[A-Za-z_!][A-Za-z0-9_]*) "
        r"(?P<static_import>\(Obj\.repr [A-Za-z_!][A-Za-z0-9_]*\)|[A-Za-z_!][A-Za-z0-9_]*) "
        r"(?P<path>\(.*?\) : string\)) "
        r"(?P<module_map>\(Obj\.repr [A-Za-z_!][A-Za-z0-9_]*\)|\([A-Za-z_!][A-Za-z0-9_]*\)|[A-Za-z_!][A-Za-z0-9_]*) "
        r"(?P<call_map>\(Obj\.repr [A-Za-z_!][A-Za-z0-9_]*\)|\([A-Za-z_!][A-Za-z0-9_]*\)|[A-Za-z_!][A-Za-z0-9_]*)",
        _expr_to_ocaml_any_local_ty_repl,
        src,
        flags=re.S,
    )
    changed = changed or src2 != src
    src = src2

    src2 = re.sub(
        r"exprToOcaml \(Obj\.magic (?P<expr>.*?)\) "
        r"arityByIdent tyCtx staticImportByIdent "
        r"\(currentPackagePath : string\) "
        r"\(Obj\.repr moduleNameByPkgAndClass\) "
        r"\(Obj\.repr callSigByCallee\)",
        r"exprToOcaml (Obj.magic \g<expr>) arityByIdent tyCtx staticImportByIdent (currentPackagePath : string) moduleNameByPkgAndClass callSigByCallee",
        src,
        flags=re.S,
    )
    changed = changed or src2 != src
    src = src2

    def _expr_to_ocaml_local_ty_repl(match: re.Match[str]) -> str:
        last = match.group("last")
        if last == "Obj.repr callSigByCallee":
            last = "callSigByCallee"
        return (
            f"exprToOcaml (Obj.magic {match.group('expr')}) "
            f"arityByIdent {match.group('ty')} staticImportByIdent "
            "(currentPackagePath : string) moduleNameByPkgAndClass "
            f"({last})"
        )

    src2 = re.sub(
        r"exprToOcaml \(Obj\.magic (?P<expr>.*?)\) \(Obj\.repr arityByIdent\) \(Obj\.repr (?P<ty>[A-Za-z_!][A-Za-z0-9_]*)\) \(Obj\.repr staticImportByIdent\) \(currentPackagePath : string\) \(Obj\.repr moduleNameByPkgAndClass\) \((?P<last>Obj\.repr callSigByCallee|Obj\.magic \(HxRuntime\.hx_null\))\)",
        _expr_to_ocaml_local_ty_repl,
        src,
        flags=re.S,
    )
    changed = changed or src2 != src
    src = src2

    def _return_expr_to_ocaml_repl(match: re.Match[str]) -> str:
        last = match.group("last")
        if last == "Obj.repr callSigByCallee":
            last = "callSigByCallee"
        return (
            f"returnExprToOcaml (Obj.{match.group('wrap')} {match.group('expr')}) "
            f"{match.group('allowed')} {match.group('ret')} "
            f"{match.group('arity')} tyByIdent staticImportByIdent "
            f"{match.group('path')} moduleNameByPkgAndClass "
            f"({last})"
        )

    src2 = re.sub(
        r"returnExprToOcaml \(Obj\.(?P<wrap>magic|obj) (?P<expr>.*?)\) (?P<allowed>[A-Za-z_!][A-Za-z0-9_]*) (?P<ret>\(Obj\.magic \(Obj\.magic \(HxRuntime\.hx_null\)\)\)|\(Obj\.magic \(TyFunctionEnv\.getReturnType .*?\)\)|\(Obj\.magic \(HxRuntime\.hx_null\)\)|\(Obj\.magic .*?\)) \(Obj\.repr (?P<arity>[A-Za-z_!][A-Za-z0-9_]*)\) \(Obj\.repr tyByIdent\) \(Obj\.repr staticImportByIdent\) (?P<path>\(.*?\) : string\)) \(Obj\.repr moduleNameByPkgAndClass\) \((?P<last>Obj\.repr callSigByCallee|Obj\.magic \(HxRuntime\.hx_null\))\)",
        _return_expr_to_ocaml_repl,
        src,
        flags=re.S,
    )
    changed = changed or src2 != src
    src = src2

    def _return_expr_to_ocaml_local_ty_repl(match: re.Match[str]) -> str:
        last = match.group("last")
        if last == "Obj.repr callSigByCallee":
            last = "callSigByCallee"
        return (
            f"returnExprToOcaml (Obj.{match.group('wrap')} {match.group('expr')}) "
            f"{match.group('allowed')} {match.group('ret')} "
            f"{match.group('arity')} {match.group('ty')} staticImportByIdent "
            f"{match.group('path')} moduleNameByPkgAndClass "
            f"({last})"
        )

    src2 = re.sub(
        r"returnExprToOcaml \(Obj\.(?P<wrap>magic|obj) (?P<expr>.*?)\) (?P<allowed>[A-Za-z_!][A-Za-z0-9_]*) (?P<ret>\(Obj\.magic \(Obj\.magic \(HxRuntime\.hx_null\)\)\)|\(Obj\.magic \(TyFunctionEnv\.getReturnType .*?\)\)|\(Obj\.magic \(HxRuntime\.hx_null\)\)|\(Obj\.magic .*?\)) \(Obj\.repr (?P<arity>[A-Za-z_!][A-Za-z0-9_]*)\) \(Obj\.repr (?P<ty>[A-Za-z_!][A-Za-z0-9_]*)\) \(Obj\.repr staticImportByIdent\) (?P<path>\(.*?\) : string\)) \(Obj\.repr moduleNameByPkgAndClass\) \((?P<last>Obj\.repr callSigByCallee|Obj\.magic \(HxRuntime\.hx_null\))\)",
        _return_expr_to_ocaml_local_ty_repl,
        src,
        flags=re.S,
    )
    changed = changed or src2 != src
    src = src2

    src2 = re.sub(
        r"returnExprToOcaml \(Obj\.(?P<wrap>magic|obj) (?P<expr>.*?)\) (?P<allowed>[A-Za-z_!][A-Za-z0-9_]*) (?P<ret>\(Obj\.magic \(Obj\.magic \(HxRuntime\.hx_null\)\)\)|\(Obj\.magic \(TyFunctionEnv\.getReturnType .*?\)\)|\(Obj\.magic \(HxRuntime\.hx_null\)\)|\(Obj\.magic .*?\)) (?P<arity>[A-Za-z_!][A-Za-z0-9_]*) (?P<ty>[A-Za-z_!][A-Za-z0-9_]*) (?P<static_import>[A-Za-z_!][A-Za-z0-9_]*) (?P<path>\(.*?\) : string\)) \(Obj\.repr moduleNameByPkgAndClass\) \((?P<last>Obj\.repr callSigByCallee|Obj\.magic \(HxRuntime\.hx_null\))\)",
        _return_expr_to_ocaml_local_ty_repl,
        src,
        flags=re.S,
    )
    changed = changed or src2 != src
    src = src2

    src2 = re.sub(
        r"returnExprToOcaml \(Obj\.magic (?P<expr>.*?)\) "
        r"(?P<allowed>[A-Za-z_!][A-Za-z0-9_]*) "
        r"(?P<ret>\(Obj\.magic \(Obj\.magic \(HxRuntime\.hx_null\)\)\)|\(Obj\.magic .*?\)) "
        r"\(Obj\.repr arityByIdent\) \(Obj\.repr tyCtx\) \(Obj\.repr staticImportByIdent\) "
        r"\(currentPackagePath : string\) "
        r"\(Obj\.repr moduleNameByPkgAndClass\) "
        r"\(Obj\.repr callSigByCallee\)",
        r"returnExprToOcaml (Obj.magic \g<expr>) \g<allowed> \g<ret> arityByIdent tyCtx staticImportByIdent (currentPackagePath : string) moduleNameByPkgAndClass callSigByCallee",
        src,
        flags=re.S,
    )
    changed = changed or src2 != src
    src = src2

    src2 = re.sub(
        r"returnExprToOcaml \(Obj\.magic (?P<expr>.*?)\) "
        r"(?P<allowed>[A-Za-z_!][A-Za-z0-9_]*) "
        r"(?P<ret>\(Obj\.magic \(Obj\.magic \(HxRuntime\.hx_null\)\)\)|\(Obj\.magic .*?\)) "
        r"arityByIdent tyCtx staticImportByIdent "
        r"\(currentPackagePath : string\) "
        r"moduleNameByPkgAndClass "
        r"\(callSigByCallee\)",
        r"returnExprToOcaml (Obj.magic \g<expr>) \g<allowed> \g<ret> arityByIdent tyCtx staticImportByIdent (currentPackagePath : string) moduleNameByPkgAndClass callSigByCallee",
        src,
        flags=re.S,
    )
    changed = changed or src2 != src
    src = src2

    literal_old = (
        'returnExprToOcaml (Obj.magic e) allowedValueIdents '
        '(Obj.magic (Obj.magic (HxRuntime.hx_null))) '
        'arityByIdent tyCtx staticImportByIdent '
        '(currentPackagePath : string) '
        '(Obj.repr moduleNameByPkgAndClass) '
        '(Obj.repr callSigByCallee)'
    )
    literal_new = (
        'returnExprToOcaml (Obj.magic e) allowedValueIdents '
        '(Obj.magic (Obj.magic (HxRuntime.hx_null))) '
        'arityByIdent tyCtx staticImportByIdent '
        '(currentPackagePath : string) '
        'moduleNameByPkgAndClass '
        'callSigByCallee'
    )
    if literal_old in src:
        src = src.replace(literal_old, literal_new)
        changed = True

    literal_obj_old = (
        'returnExprToOcaml (Obj.obj (HxEnum.unbox_or_obj "HxExpr" init)) allowedValueIdents '
        '(Obj.magic (Obj.magic (HxRuntime.hx_null))) '
        '(Obj.repr arityByIdent) (Obj.repr tyCtx) (Obj.repr staticImportByIdent) '
        '(currentPackagePath : string) '
        '(Obj.repr moduleNameByPkgAndClass) '
        '(Obj.repr callSigByCallee)'
    )
    literal_obj_new = (
        'returnExprToOcaml (Obj.obj (HxEnum.unbox_or_obj "HxExpr" init)) allowedValueIdents '
        '(Obj.magic (Obj.magic (HxRuntime.hx_null))) '
        'arityByIdent tyCtx staticImportByIdent '
        '(currentPackagePath : string) '
        'moduleNameByPkgAndClass '
        'callSigByCallee'
    )
    if literal_obj_old in src:
        src = src.replace(literal_obj_old, literal_obj_new)
        changed = True

    literal_stmt_old = (
        'stmtListToOcaml (Obj.magic stmts) allowed (exc : string) '
        '(Obj.repr arityByName) (Obj.repr tyByIdent) (Obj.repr staticImportByIdent) '
        '(HxModuleDecl.getPackagePath (Obj.magic decl) : string) '
        '(Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee) '
        '(Obj.repr localTypeHints) (Obj.repr fnReturnTypesByName)'
    )
    literal_stmt_new = (
        'stmtListToOcaml (Obj.magic stmts) allowed (exc : string) '
        '(Obj.magic arityByName) tyByIdent (Obj.magic staticImportByIdent) '
        '(HxModuleDecl.getPackagePath (Obj.magic decl) : string) '
        '(Obj.repr moduleNameByPkgAndClass) (Obj.magic callSigByCallee) '
        'localTypeHints fnReturnTypesByName'
    )
    if literal_stmt_old in src:
        src = src.replace(literal_stmt_old, literal_stmt_new)
        changed = True

    literal_stmt_old_alt = (
        'stmtListToOcaml (Obj.magic stmts) allowed (exc : string) '
        '(Obj.repr arityByName) (Obj.repr tyByIdent) (Obj.repr staticImportByIdent) '
        '(HxModuleDecl.getPackagePath (Obj.magic decl) : string) '
        'moduleNameByPkgAndClass (callSigByCallee) '
        '(Obj.repr localTypeHints) (Obj.repr fnReturnTypesByName)'
    )
    literal_stmt_new_alt = (
        'stmtListToOcaml (Obj.magic stmts) allowed (exc : string) '
        '(Obj.magic arityByName) tyByIdent (Obj.magic staticImportByIdent) '
        '(HxModuleDecl.getPackagePath (Obj.magic decl) : string) '
        '(Obj.repr moduleNameByPkgAndClass) (Obj.magic callSigByCallee) '
        'localTypeHints fnReturnTypesByName'
    )
    if literal_stmt_old_alt in src:
        src = src.replace(literal_stmt_old_alt, literal_stmt_new_alt)
        changed = True

    literal_expr_old = (
        'exprToOcaml (Obj.magic branchExpr) arityByIdent localTy staticImportByIdent '
        '(currentPackagePath : string) '
        '(Obj.repr moduleNameByPkgAndClass) '
        '(Obj.repr callSigByCallee)'
    )
    literal_expr_new = (
        'exprToOcaml (Obj.magic branchExpr) arityByIdent (Obj.magic localTy) staticImportByIdent '
        '(currentPackagePath : string) '
        'moduleNameByPkgAndClass '
        'callSigByCallee'
    )
    if literal_expr_old in src:
        src = src.replace(literal_expr_old, literal_expr_new)
        changed = True

    src2 = re.sub(
        r"exprToOcaml \(Obj\.magic branchExpr\) arityByIdent localTy staticImportByIdent "
        r"\(currentPackagePath : string\) moduleNameByPkgAndClass callSigByCallee",
        r"exprToOcaml (Obj.magic branchExpr) arityByIdent (Obj.magic localTy) staticImportByIdent (currentPackagePath : string) moduleNameByPkgAndClass callSigByCallee",
        src,
    )
    changed = changed or src2 != src
    src = src2

    src2 = re.sub(
        r"exprToOcaml \(Obj\.(?P<wrap>magic|obj) (?P<expr>.*?)\) "
        r"arityByIdent (?P<tylocal>ty[0-9]+) staticImportByIdent "
        r"\(currentPackagePath : string\) "
        r"\(Obj\.repr moduleNameByPkgAndClass\) "
        r"\(Obj\.magic \(HxRuntime\.hx_null\)\)",
        r"exprToOcaml (Obj.\g<wrap> \g<expr>) arityByIdent (Obj.magic \g<tylocal>) staticImportByIdent (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.magic (HxRuntime.hx_null))",
        src,
        flags=re.S,
    )
    changed = changed or src2 != src
    src = src2

    src2 = re.sub(
        r"exprToOcaml \(Obj\.(?P<wrap>magic|obj) (?P<expr>.*?)\) "
        r"arityByIdent tyCtx staticImportByIdent "
        r"\(currentPackagePath : string\) "
        r"moduleNameByPkgAndClass callSigByCallee",
        r"exprToOcaml (Obj.\g<wrap> \g<expr>) arityByIdent (Obj.magic tyCtx) staticImportByIdent (currentPackagePath : string) moduleNameByPkgAndClass callSigByCallee",
        src,
        flags=re.S,
    )
    changed = changed or src2 != src
    src = src2

    src2 = re.sub(
        r"returnExprToOcaml \(Obj\.(?P<wrap>magic|obj) (?P<expr>.*?)\) "
        r"(?P<allowed>[A-Za-z_!][A-Za-z0-9_]*) "
        r"(?P<ret>\(Obj\.magic \(Obj\.magic \(HxRuntime\.hx_null\)\)\)|\(Obj\.magic .*?\)) "
        r"arityByIdent tyCtx staticImportByIdent "
        r"\(currentPackagePath : string\) "
        r"moduleNameByPkgAndClass callSigByCallee",
        r"returnExprToOcaml (Obj.\g<wrap> \g<expr>) \g<allowed> \g<ret> arityByIdent (Obj.magic tyCtx) staticImportByIdent (currentPackagePath : string) moduleNameByPkgAndClass callSigByCallee",
        src,
        flags=re.S,
    )
    changed = changed or src2 != src
    src = src2

    src2 = src.replace(
        "condToOcamlBool (Obj.magic cond) tyCtx",
        "condToOcamlBool (Obj.magic cond) (Obj.magic tyCtx)",
    )
    changed = changed or src2 != src
    src = src2

    literal_static_expr_old = (
        'exprToOcaml (Obj.obj (HxEnum.unbox_or_obj "HxExpr" init)) '
        '(HxMap.create_string ()) staticTyByIdent (HxMap.create_string ()) '
        '(HxModuleDecl.getPackagePath (Obj.magic decl) : string) '
        'moduleNameByPkgAndClass globalCallSigByCallee'
    )
    literal_static_expr_new = (
        'exprToOcaml (Obj.obj (HxEnum.unbox_or_obj "HxExpr" init)) '
        '(Obj.magic (HxMap.create_string ())) (Obj.magic staticTyByIdent) (Obj.magic (HxMap.create_string ())) '
        '(HxModuleDecl.getPackagePath (Obj.magic decl) : string) '
        '(Obj.repr moduleNameByPkgAndClass) (Obj.magic globalCallSigByCallee)'
    )
    if literal_static_expr_old in src:
        src = src.replace(literal_static_expr_old, literal_static_expr_new)
        changed = True

    literal_return_old = (
        'returnExprToOcaml (Obj.magic (HxFunctionDecl.getFirstReturnExpr (Obj.magic parsedFn) ())) '
        'allowed (Obj.magic (TyFunctionEnv.getReturnType (Obj.magic tf) ())) '
        'arityByName tyByIdent staticImportByIdent '
        '(HxModuleDecl.getPackagePath (Obj.magic decl) : string) '
        'moduleNameByPkgAndClass (callSigByCallee)'
    )
    literal_return_new = (
        'returnExprToOcaml (Obj.magic (HxFunctionDecl.getFirstReturnExpr (Obj.magic parsedFn) ())) '
        'allowed (Obj.magic (TyFunctionEnv.getReturnType (Obj.magic tf) ())) '
        '(Obj.magic arityByName) (Obj.magic tyByIdent) (Obj.magic staticImportByIdent) '
        '(HxModuleDecl.getPackagePath (Obj.magic decl) : string) '
        '(Obj.repr moduleNameByPkgAndClass) (Obj.magic callSigByCallee)'
    )
    if literal_return_old in src:
        src = src.replace(literal_return_old, literal_return_new)
        changed = True

    literal_expr_direct_old = (
        'exprToOcaml (Obj.obj (HxEnum.unbox_or_obj "HxExpr" init)) '
        'arityByName staticTyByIdent staticImportByIdent '
        '(HxModuleDecl.getPackagePath (Obj.magic decl) : string) '
        'moduleNameByPkgAndClass callSigByCallee'
    )
    literal_expr_direct_new = (
        'exprToOcaml (Obj.obj (HxEnum.unbox_or_obj "HxExpr" init)) '
        '(Obj.magic arityByName) (Obj.magic staticTyByIdent) (Obj.magic staticImportByIdent) '
        '(HxModuleDecl.getPackagePath (Obj.magic decl) : string) '
        '(Obj.repr moduleNameByPkgAndClass) (Obj.magic callSigByCallee)'
    )
    if literal_expr_direct_old in src:
        src = src.replace(literal_expr_direct_old, literal_expr_direct_new)
        changed = True

    literal_extend_ty_old = (
        'extendTyByIdentMany (Obj.repr tyByIdent) '
        '(Obj.magic args) '
        '(Obj.magic (TyType.fromHintText ("Dynamic" : string)))'
    )
    literal_extend_ty_new = (
        'extendTyByIdentMany (Obj.magic tyByIdent) '
        '(Obj.magic args) '
        '(Obj.magic (TyType.fromHintText ("Dynamic" : string)))'
    )
    if literal_extend_ty_old in src:
        src = src.replace(literal_extend_ty_old, literal_extend_ty_new)
        changed = True

    literal_extend_ty_direct_old = (
        'extendTyByIdentMany tyByIdent '
        '(Obj.magic args) '
        '(Obj.magic (TyType.fromHintText ("Dynamic" : string)))'
    )
    literal_extend_ty_direct_new = (
        'extendTyByIdentMany (Obj.magic tyByIdent) '
        '(Obj.magic args) '
        '(Obj.magic (TyType.fromHintText ("Dynamic" : string)))'
    )
    if literal_extend_ty_direct_old in src:
        src = src.replace(literal_extend_ty_direct_old, literal_extend_ty_direct_new)
        changed = True

    literal_extend_one_old = (
        'extendTyByIdent (Obj.repr tyByIdent) '
        '(name : string) '
        '(Obj.magic (TyType.fromHintText ("Dynamic" : string)))'
    )
    literal_extend_one_new = (
        'extendTyByIdent (Obj.magic tyByIdent) '
        '(name : string) '
        '(Obj.magic (TyType.fromHintText ("Dynamic" : string)))'
    )
    if literal_extend_one_old in src:
        src = src.replace(literal_extend_one_old, literal_extend_one_new)
        changed = True

    literal_extend_one_direct_old = (
        'extendTyByIdent tyByIdent '
        '(name : string) '
        '(Obj.magic (TyType.fromHintText ("Dynamic" : string)))'
    )
    literal_extend_one_direct_new = (
        'extendTyByIdent (Obj.magic tyByIdent) '
        '(name : string) '
        '(Obj.magic (TyType.fromHintText ("Dynamic" : string)))'
    )
    if literal_extend_one_direct_old in src:
        src = src.replace(literal_extend_one_direct_old, literal_extend_one_direct_new)
        changed = True

    src2 = re.sub(
        r"extendTyByIdentMany \(Obj\.repr (?P<tymap>[A-Za-z_!][A-Za-z0-9_]*)\)",
        r"extendTyByIdentMany (Obj.magic \g<tymap>)",
        src,
    )
    changed = changed or src2 != src
    src = src2

    src2 = re.sub(
        r"extendTyByIdent \(Obj\.repr (?P<tymap>[A-Za-z_!][A-Za-z0-9_]*)\)",
        r"extendTyByIdent (Obj.magic \g<tymap>)",
        src,
    )
    changed = changed or src2 != src
    src = src2

    def _normalize_ident_arg(raw: str) -> str:
        raw = raw.strip()
        if raw.startswith("(Obj.repr ") and raw.endswith(")"):
            return raw[len("(Obj.repr ") : -1]
        return raw

    def _stmt_list_to_ocaml_general_repl(match: re.Match[str]) -> str:
        return (
            f"stmtListToOcaml (Obj.magic {match.group('stmts')}) "
            f"{match.group('allowed')} {match.group('ret')} "
            f"{match.group('arity')} {match.group('ty')} {match.group('static_import')} "
            f"{match.group('path')} {_normalize_ident_arg(match.group('module_map'))} "
            f"{_normalize_ident_arg(match.group('call_map'))} "
            f"{match.group('local_hints')} {match.group('fn_returns')}"
        )

    src2 = re.sub(
        r"stmtListToOcaml \(Obj\.magic (?P<stmts>.*?)\) "
        r"(?P<allowed>[A-Za-z_!][A-Za-z0-9_]*) "
        r"(?P<ret>\(.*?: string\)|[A-Za-z_!][A-Za-z0-9_]*) "
        r"\(Obj\.repr (?P<arity>[A-Za-z_!][A-Za-z0-9_]*)\) "
        r"\(Obj\.repr (?P<ty>[A-Za-z_!][A-Za-z0-9_]*)\) "
        r"\(Obj\.repr (?P<static_import>[A-Za-z_!][A-Za-z0-9_]*)\) "
        r"(?P<path>\(.*?\) : string\)) "
        r"(?P<module_map>\(Obj\.repr [A-Za-z_!][A-Za-z0-9_]*\)|[A-Za-z_!][A-Za-z0-9_]*) "
        r"(?P<call_map>\(Obj\.repr [A-Za-z_!][A-Za-z0-9_]*\)|[A-Za-z_!][A-Za-z0-9_]*) "
        r"\(Obj\.repr (?P<local_hints>[A-Za-z_!][A-Za-z0-9_]*)\) "
        r"\(Obj\.repr (?P<fn_returns>[A-Za-z_!][A-Za-z0-9_]*)\)",
        _stmt_list_to_ocaml_general_repl,
        src,
        flags=re.S,
    )
    changed = changed or src2 != src
    src = src2

    def _stmt_list_to_ocaml_repl(match: re.Match[str]) -> str:
        return (
            f"stmtListToOcaml (Obj.magic {match.group('stmts')}) "
            f"{match.group('allowed')} {match.group('ret')} "
            f"arityByIdent {match.group('ty')} staticImportByIdent "
            "(currentPackagePath : string) moduleNameByPkgAndClass "
            "callSigByCallee localHints fnReturnTypes"
        )

    src2 = re.sub(
        r"stmtListToOcaml \(Obj\.magic (?P<stmts>.*?)\) "
        r"(?P<allowed>[A-Za-z_!][A-Za-z0-9_]*) "
        r"(?P<ret>\(returnExc : string\)|[A-Za-z_!][A-Za-z0-9_]*) "
        r"\(Obj\.repr arityByIdent\) "
        r"\(Obj\.repr (?P<ty>[A-Za-z_!][A-Za-z0-9_]*)\) "
        r"\(Obj\.repr staticImportByIdent\) "
        r"\(currentPackagePath : string\) "
        r"\(Obj\.repr moduleNameByPkgAndClass\) "
        r"\(Obj\.repr callSigByCallee\) "
        r"\(Obj\.repr localHints\) "
        r"\(Obj\.repr fnReturnTypes\)",
        _stmt_list_to_ocaml_repl,
        src,
        flags=re.S,
    )
    changed = changed or src2 != src
    src = src2

    src2 = re.sub(
        r"mutableAssignmentStmtToUnit "
        r"\((?P<op>.*?): string\) "
        r"\((?P<name>.*?): string\) "
        r"\(Obj\.magic (?P<rhs>.*?)\) "
        r"\(Obj\.repr (?P<ty>[A-Za-z_!][A-Za-z0-9_]*)\)",
        r"mutableAssignmentStmtToUnit (\g<op> : string) (\g<name> : string) (Obj.magic \g<rhs>) \g<ty>",
        src,
        flags=re.S,
    )
    changed = changed or src2 != src
    src = src2

    if not changed:
        return

    write_text(path_str, src)


def cmd_patch_extend_ty_ident_call_reprs(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-extend-ty-ident-call-reprs <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    if (
        "extendTyByIdent (Obj.repr " not in src
        and "extendTyByIdentMany (Obj.repr " not in src
        and "extendTyByIdent tyByIdent " not in src
        and "extendTyByIdentMany tyByIdent " not in src
    ):
        return

    changed = False

    src2 = src.replace(
        'extendTyByIdentMany (Obj.repr tyByIdent) (Obj.magic args) (Obj.magic (TyType.fromHintText ("Dynamic" : string)))',
        'extendTyByIdentMany (Obj.magic tyByIdent) (Obj.magic args) (Obj.magic (TyType.fromHintText ("Dynamic" : string)))',
    )
    changed = changed or src2 != src
    src = src2

    src2 = src.replace(
        'extendTyByIdentMany tyByIdent (Obj.magic args) (Obj.magic (TyType.fromHintText ("Dynamic" : string)))',
        'extendTyByIdentMany (Obj.magic tyByIdent) (Obj.magic args) (Obj.magic (TyType.fromHintText ("Dynamic" : string)))',
    )
    changed = changed or src2 != src
    src = src2

    src2 = src.replace(
        'extendTyByIdent (Obj.repr tyByIdent) (name : string) (Obj.magic (TyType.fromHintText ("Dynamic" : string)))',
        'extendTyByIdent (Obj.magic tyByIdent) (name : string) (Obj.magic (TyType.fromHintText ("Dynamic" : string)))',
    )
    changed = changed or src2 != src
    src = src2

    src2 = src.replace(
        'extendTyByIdent tyByIdent (name : string) (Obj.magic (TyType.fromHintText ("Dynamic" : string)))',
        'extendTyByIdent (Obj.magic tyByIdent) (name : string) (Obj.magic (TyType.fromHintText ("Dynamic" : string)))',
    )
    changed = changed or src2 != src
    src = src2

    src2 = re.sub(
        r"extendTyByIdentMany \(Obj\.repr (?P<tymap>[A-Za-z_!][A-Za-z0-9_]*)\)",
        r"extendTyByIdentMany (Obj.magic \g<tymap>)",
        src,
    )
    changed = changed or src2 != src
    src = src2

    src2 = re.sub(
        r"extendTyByIdent \(Obj\.repr (?P<tymap>[A-Za-z_!][A-Za-z0-9_]*)\)",
        r"extendTyByIdent (Obj.magic \g<tymap>)",
        src,
    )
    changed = changed or src2 != src
    src = src2

    if changed:
        write_text(path_str, src)


def cmd_patch_stmt_list_local_hint_reprs(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-stmt-list-local-hint-reprs <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    if (
        "stmtListToOcaml (Obj.magic " not in src
        or (
            "(Obj.repr localHints) (Obj.repr fnReturnTypes)" not in src
            and "(Obj.repr localTypeHints) (Obj.repr fnReturnTypesByName)" not in src
        )
    ):
        return

    changed = False

    literal_stmt_old = (
        'stmtListToOcaml (Obj.magic stmts) allowed (exc : string) '
        '(Obj.repr arityByName) (Obj.repr tyByIdent) (Obj.repr staticImportByIdent) '
        '(HxModuleDecl.getPackagePath (Obj.magic decl) : string) '
        '(Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee) '
        '(Obj.repr localTypeHints) (Obj.repr fnReturnTypesByName)'
    )
    literal_stmt_new = (
        'stmtListToOcaml (Obj.magic stmts) allowed (exc : string) '
        '(Obj.magic arityByName) tyByIdent (Obj.magic staticImportByIdent) '
        '(HxModuleDecl.getPackagePath (Obj.magic decl) : string) '
        '(Obj.repr moduleNameByPkgAndClass) (Obj.magic callSigByCallee) '
        'localTypeHints fnReturnTypesByName'
    )
    if literal_stmt_old in src:
        src = src.replace(literal_stmt_old, literal_stmt_new)
        changed = True

    def _stmt_list_to_ocaml_repl(match: re.Match[str]) -> str:
        return (
            f"stmtListToOcaml (Obj.magic {match.group('stmts')}) "
            f"{match.group('allowed')} {match.group('ret')} "
            f"arityByIdent {match.group('ty')} staticImportByIdent "
            "(currentPackagePath : string) moduleNameByPkgAndClass "
            "callSigByCallee localHints fnReturnTypes"
        )

    src2 = re.sub(
        r"stmtListToOcaml \(Obj\.magic (?P<stmts>.*?)\) "
        r"(?P<allowed>[A-Za-z_!][A-Za-z0-9_]*) "
        r"(?P<ret>\(returnExc : string\)|[A-Za-z_!][A-Za-z0-9_]*) "
        r"\(Obj\.repr arityByIdent\) "
        r"\(Obj\.repr (?P<ty>[A-Za-z_!][A-Za-z0-9_]*)\) "
        r"\(Obj\.repr staticImportByIdent\) "
        r"\(currentPackagePath : string\) "
        r"\(Obj\.repr moduleNameByPkgAndClass\) "
        r"\(Obj\.repr callSigByCallee\) "
        r"\(Obj\.repr localHints\) "
        r"\(Obj\.repr fnReturnTypes\)",
        _stmt_list_to_ocaml_repl,
        src,
        flags=re.S,
    )
    changed = changed or src2 != src
    src = src2

    if changed:
        write_text(path_str, src)


def cmd_patch_stmt_list_string_builder(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-stmt-list-string-builder <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    marker = "let base = ref (\"()\" : string) in let prefixes = ref ([] : string list) in let suffixes = ref ([] : string list)"
    if marker in src:
        return

    start_marker = 'let out = ref ("()" : string) in ('
    start = src.find(start_marker)
    if start == -1:
        return

    end_rx = re.compile(
        r"""ignore \(let __assign_\d+ = Obj\.magic \(!tempArray\) in \(\n"""
        r"""\s*currentMutableLocalRefNames := __assign_\d+;\n"""
        r"""\s*__assign_\d+\n"""
        r"""\s*\)\);\n"""
        r"""\s*ignore \(let __assign_\d+ = Obj\.repr previousStmtLocalTypeHints in \(\n"""
        r"""\s*currentFunctionLocalTypeHints := __assign_\d+;\n"""
        r"""\s*__assign_\d+\n"""
        r"""\s*\)\);\n"""
        r"""\s*!out""",
        re.S,
    )
    end_match = end_rx.search(src, start)
    if end_match is None:
        fail("build-hxhx: failed to locate stmtListToOcaml generated fold end for string-builder repair\n")

    replacement = '''let base = ref ("()" : string) in let prefixes = ref ([] : string list) in let suffixes = ref ([] : string list) in (
                        let add_wrap = fun prefix suffix -> (
                          prefixes := prefix :: !prefixes;
                          suffixes := suffix :: !suffixes
                        ) in let reset_to_returning = fun rendered -> (
                          base := rendered;
                          prefixes := [];
                          suffixes := []
                        ) in (
                        ignore (let _g = ref 0 in let _g1 = HxArray.length stmts in while !_g < _g1 do ignore (let i = let __old_stmtlist_string_builder_i = !_g in let __new_stmtlist_string_builder_i = HxInt.add __old_stmtlist_string_builder_i 1 in (
                          ignore (_g := __new_stmtlist_string_builder_i);
                          __old_stmtlist_string_builder_i
                        ) in let idx = HxInt.sub (HxInt.sub (HxArray.length stmts) 1) i in let s = Obj.magic (HxArray.get (Obj.magic stmts) idx) in let tyCtx = extendTyWithLocals tyByIdent (HxArray.get (Obj.magic localsBefore) idx) in let prevStmtTyEntries = Obj.magic (!currentStmtTyEntries) in (
                          ignore (let __assign_stmtlist_string_builder_entries = Obj.magic (buildStmtTyEntries tyCtx) in (
                            currentStmtTyEntries := __assign_stmtlist_string_builder_entries;
                            __assign_stmtlist_string_builder_entries
                          ));
                          ignore (match s with
                            | HxStmt.SVar (name, _typeHint, init, _pos) -> (
                              let rhs = if init == Obj.magic (HxRuntime.hx_null) then ("(Obj.magic 0)" : string) else (
                                let initExpr = Obj.obj (HxEnum.unbox_or_obj "HxExpr" init) in match initExpr with
                                | HxExpr.EIdent n when HxString.equals n name -> ("(Obj.magic 0)" : string)
                                | _ -> (returnExprToOcaml (Obj.magic initExpr) allowedValueIdents (Obj.magic (Obj.magic (HxRuntime.hx_null))) (Obj.repr arityByIdent) (Obj.repr tyCtx) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee) : string)
                              ) in let ident = (ocamlValueIdent (name : string) : string) in
                              if isMutableLocalRefIdent (name : string) then
                                add_wrap (("let " ^ HxString.toStdString ident) ^ " = ref (" ^ HxString.toStdString rhs ^ ") in (ignore " ^ HxString.toStdString ident ^ "; (" : string) ("))" : string)
                              else
                                add_wrap (("let " ^ HxString.toStdString ident) ^ " = " ^ HxString.toStdString rhs ^ " in (ignore " ^ HxString.toStdString ident ^ "; (" : string) ("))" : string)
                            )
                            | HxStmt.SIf (cond, thenBranch, elseBranch, _pos) -> (
                              let rec unwrapSingleAssign = fun b -> match b with
                                | HxStmt.SExpr (HxExpr.EBinop (op, HxExpr.EIdent name, rhs), _) when HxString.equals op "=" -> Some (name, rhs)
                                | HxStmt.SBlock (ss, _) when ss != Obj.magic (HxRuntime.hx_null) && HxArray.length ss = 1 ->
                                  unwrapSingleAssign (Obj.magic (HxArray.get (Obj.magic ss) 0))
                                | _ -> None
                              in let isNullCheckFor = fun name c -> match c with
                                | HxExpr.EBinop (op, HxExpr.EIdent n, HxExpr.ENull) when HxString.equals op "==" -> HxString.equals n name
                                | HxExpr.EBinop (op, HxExpr.ENull, HxExpr.EIdent n) when HxString.equals op "==" -> HxString.equals n name
                                | _ -> false
                              in let assign = if elseBranch == Obj.magic (HxRuntime.hx_null) then unwrapSingleAssign (Obj.magic thenBranch) else None in
                              match assign with
                              | Some (assignName, assignRhs) when isNullCheckFor (assignName : string) (Obj.magic cond) && not (isMutableLocalRefIdent (assignName : string)) ->
                                let ident = (ocamlValueIdent (assignName : string) : string) in
                                let rhs = (returnExprToOcaml (Obj.magic assignRhs) allowedValueIdents (Obj.magic (Obj.magic (HxRuntime.hx_null))) (Obj.repr arityByIdent) (Obj.repr tyCtx) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee) : string) in
                                add_wrap (((((((("(let " ^ HxString.toStdString ident) ^ " = (if ") ^ HxString.toStdString (condToOcamlBool (Obj.magic cond) tyCtx)) ^ " then (") ^ HxString.toStdString rhs) ^ ") else ") ^ HxString.toStdString ident) ^ ") in (ignore " ^ HxString.toStdString ident ^ "; (" : string) (")))" : string)
                              | _ ->
                                if (!stmtAlwaysReturns) (Obj.magic s) then
                                  reset_to_returning (((!stmtToUnit) (Obj.magic s) tyCtx : string))
                                else
                                  add_wrap ((("(" ^ HxString.toStdString ((!stmtToUnit) (Obj.magic s) tyCtx)) ^ "; " : string)) (")" : string)
                            )
                            | _ -> (
                              if (!stmtAlwaysReturns) (Obj.magic s) then
                                reset_to_returning (((!stmtToUnit) (Obj.magic s) tyCtx : string))
                              else
                                add_wrap ((("(" ^ HxString.toStdString ((!stmtToUnit) (Obj.magic s) tyCtx)) ^ "; " : string)) (")" : string)
                            ));
                          let __assign_stmtlist_string_builder_prev_entries = Obj.magic prevStmtTyEntries in (
                            currentStmtTyEntries := __assign_stmtlist_string_builder_prev_entries;
                            __assign_stmtlist_string_builder_prev_entries
                          )
                        )) done);
                        ignore (let __assign_stmtlist_string_builder_mutables = Obj.magic (!tempArray) in (
                          currentMutableLocalRefNames := __assign_stmtlist_string_builder_mutables;
                          __assign_stmtlist_string_builder_mutables
                        ));
                        ignore (let __assign_stmtlist_string_builder_hints = Obj.repr previousStmtLocalTypeHints in (
                          currentFunctionLocalTypeHints := __assign_stmtlist_string_builder_hints;
                          __assign_stmtlist_string_builder_hints
                        ));
                        let __stmtlist_string_builder_out = Buffer.create 1024 in (
                          ignore (List.iter (fun part -> Buffer.add_string __stmtlist_string_builder_out part) (!prefixes));
                          ignore (Buffer.add_string __stmtlist_string_builder_out (!base));
                          ignore (List.iter (fun part -> Buffer.add_string __stmtlist_string_builder_out part) (List.rev (!suffixes)));
                          Buffer.contents __stmtlist_string_builder_out
                        )
                        )'''

    src = src[:start] + replacement + src[end_match.end():]
    write_text(path_str, src)


def cmd_patch_stmt_list_trace(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-stmt-list-trace <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    if "stmt_list_begin:" in src:
        return

    begin_anchor = """                          ));
                          ignore (match s with
"""
    begin_patch = """                          ));
                          let __stmtlist_trace_kind_pos = match s with
                            | HxStmt.SBlock (_, pos) -> ("SBlock", pos)
                            | HxStmt.SVar (_, _, _, pos) -> ("SVar", pos)
                            | HxStmt.SIf (_, _, _, pos) -> ("SIf", pos)
                            | HxStmt.SForIn (_, _, _, pos) -> ("SForIn", pos)
                            | HxStmt.SWhile (_, _, pos) -> ("SWhile", pos)
                            | HxStmt.SDoWhile (_, _, pos) -> ("SDoWhile", pos)
                            | HxStmt.SSwitch (_, _, _, pos) -> ("SSwitch", pos)
                            | HxStmt.STry (_, _, pos) -> ("STry", pos)
                            | HxStmt.SBreak pos -> ("SBreak", pos)
                            | HxStmt.SContinue pos -> ("SContinue", pos)
                            | HxStmt.SThrow (_, pos) -> ("SThrow", pos)
                            | HxStmt.SReturnVoid pos -> ("SReturnVoid", pos)
                            | HxStmt.SReturn (_, pos) -> ("SReturn", pos)
                            | HxStmt.SExpr (_, pos) -> ("SExpr", pos)
                          in let (__stmtlist_trace_kind, __stmtlist_trace_pos) = __stmtlist_trace_kind_pos in let __stmtlist_trace_line = HxPos.getLine (Obj.magic __stmtlist_trace_pos) () in let __stmtlist_trace_col = HxPos.getColumn (Obj.magic __stmtlist_trace_pos) () in
                          ignore (if not (!currentFunctionName == Obj.magic (HxRuntime.hx_null)) && HxString.equals (!currentFunctionName) "emitToDir" then _emitterstagedebug_traceStage3Phase (((((((((("stmt_list_begin:" ^ HxString.toStdString (!currentFunctionName)) ^ ":") ^ string_of_int idx) ^ "/") ^ string_of_int (HxArray.length stmts)) ^ ":") ^ __stmtlist_trace_kind) ^ ":line=") ^ string_of_int __stmtlist_trace_line) ^ ":col=" ^ string_of_int __stmtlist_trace_col : string) else ());
                          ignore (match s with
"""
    src = replace_one(
        src,
        begin_anchor,
        begin_patch,
        "build-hxhx: failed to locate stmtListToOcaml generated trace begin anchor\n",
    )

    done_anchor = """                            ));
                          let __assign_stmtlist_string_builder_prev_entries = Obj.magic prevStmtTyEntries in (
"""
    done_patch = """                            ));
                          ignore (if not (!currentFunctionName == Obj.magic (HxRuntime.hx_null)) && HxString.equals (!currentFunctionName) "emitToDir" then _emitterstagedebug_traceStage3Phase (((((((((("stmt_list_done:" ^ HxString.toStdString (!currentFunctionName)) ^ ":") ^ string_of_int idx) ^ "/") ^ string_of_int (HxArray.length stmts)) ^ ":") ^ __stmtlist_trace_kind) ^ ":line=") ^ string_of_int __stmtlist_trace_line) ^ ":col=" ^ string_of_int __stmtlist_trace_col : string) else ());
                          let __assign_stmtlist_string_builder_prev_entries = Obj.magic prevStmtTyEntries in (
"""
    src = replace_one(
        src,
        done_anchor,
        done_patch,
        "build-hxhx: failed to locate stmtListToOcaml generated trace done anchor\n",
    )

    write_text(path_str, src)


def cmd_patch_module_name_lookup_raw_map(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-module-name-lookup-raw-map <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    if "moduleNameByPkgAndClassRaw" in src or "typedMapGet moduleNameByPkgAndClass" not in src:
        return

    pattern = re.compile(
        r"""(?P<prefix>and exprToOcaml = fun e .*? moduleNameByPkgAndClass callSigByCallee -> try let __fallback_result_(?P<outer>\d+) = )"""
        r"""(?P<body>let moduleNameForKey = fun key -> try let __fallback_result_(?P<inner>\d+) = let resolved = \(typedMapGet moduleNameByPkgAndClass \(key : string\) : string\) in \()""",
        re.S,
    )
    match = pattern.search(src)
    if match is None:
        return

    replacement = (
        f"{match.group('prefix')}"
        "let moduleNameByPkgAndClassRaw = Obj.magic moduleNameByPkgAndClass in "
        f"let moduleNameForKey = fun key -> try let __fallback_result_{match.group('inner')} = "
        "let resolved = (mapGetRaw moduleNameByPkgAndClassRaw (key : string) : string) in ("
    )
    src = src[:match.start()] + replacement + src[match.end():]
    write_text(path_str, src)


def cmd_patch_typed_ty_ident_lookups(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-typed-ty-ident-lookups <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    if "let tyForIdent = fun name" not in src and "mapGetRaw (Obj.repr tyByIdent)" not in src:
        return

    old = """| HxRuntime.Hx_return __ret_236 -> Obj.obj __ret_236 in let tyForIdent = fun name -> try let __fallback_result_242 = let tempString = ref (\"\" : string) in (
  ignore (if mapGetRaw (Obj.repr tyByIdent) (name : string) != Obj.magic (HxRuntime.hx_null) then let __assign_238 = (name : string) in (
    tempString := __assign_238;
    __assign_238
  ) else let lowered = (ocamlValueIdent (name : string) : string) in if not (HxString.equals lowered name) && mapGetRaw (Obj.repr tyByIdent) (lowered : string) != Obj.magic (HxRuntime.hx_null) then let __assign_239 = (lowered : string) in (
    tempString := __assign_239;
    __assign_239
  ) else let __assign_240 = (name : string) in (
    tempString := __assign_240;
    __assign_240
  ));
  let resolved = mapGetRaw (Obj.repr tyByIdent) (!tempString : string) in (
    ignore (if resolved == Obj.magic (HxRuntime.hx_null) then raise (HxRuntime.Hx_return (Obj.repr (\"\" : string))) else ());
    let t = Obj.magic resolved in (
      ignore (if t == Obj.magic (HxRuntime.hx_null) then raise (HxRuntime.Hx_return (Obj.repr (\"\" : string))) else ());
      TyType.toString (Obj.magic t) ()
    )
  )
) in Obj.magic __fallback_result_242 with
  | HxRuntime.Hx_return __ret_241 -> Obj.obj __ret_241 in let isIntExpr = ref"""
    new = """| HxRuntime.Hx_return __ret_236 -> Obj.obj __ret_236 in let getTyIdentRaw = fun name -> let typedTyByIdent = Obj.magic tyByIdent in if typedTyByIdent == Obj.magic (HxRuntime.hx_null) then Obj.magic (HxRuntime.hx_null) else Obj.magic (HxMap.get_string typedTyByIdent name) in let resolveTyIdentName = fun name -> if getTyIdentRaw (name : string) != Obj.magic (HxRuntime.hx_null) then name else let lowered = (ocamlValueIdent (name : string) : string) in if not (HxString.equals lowered name) && getTyIdentRaw (lowered : string) != Obj.magic (HxRuntime.hx_null) then lowered else name in let tyForIdent = fun name -> try let __fallback_result_242 = let resolved = (getTyIdentRaw (resolveTyIdentName (name : string)) : Obj.t) in (
  ignore (if resolved == Obj.magic (HxRuntime.hx_null) then raise (HxRuntime.Hx_return (Obj.repr (\"\" : string))) else ());
  let t = Obj.magic resolved in (
    ignore (if t == Obj.magic (HxRuntime.hx_null) then raise (HxRuntime.Hx_return (Obj.repr (\"\" : string))) else ());
    TyType.toString (Obj.magic t) ()
  )
) in Obj.magic __fallback_result_242 with
  | HxRuntime.Hx_return __ret_241 -> Obj.obj __ret_241 in let isIntExpr = ref"""
    if old in src:
        src = replace_one(
            src,
            old,
            new,
            "build-hxhx: failed to locate bootstrap tyForIdent lookup anchor in EmitterStage.ml\n",
        )
        write_text(path_str, src)
        return

    current_shape = re.compile(
        r"""in let tyForIdent = fun name -> try let __fallback_result_(?P<result>\d+) = let (?P<temp>tempString\d+) = ref \("" : string\) in \(
  ignore \(if typedMapGet (?:tyByIdent|\(Obj\.repr tyByIdent\)) \(name : string\) != Obj\.magic \(HxRuntime\.hx_null\) then let __assign_(?P<a>\d+) = \(name : string\) in \(
    (?P=temp) := __assign_(?P=a);
    __assign_(?P=a)
  \) else let lowered = \(ocamlValueIdent \(name : string\) : string\) in if not \(HxString\.equals lowered name\) && typedMapGet (?:tyByIdent|\(Obj\.repr tyByIdent\)) \(lowered : string\) != Obj\.magic \(HxRuntime\.hx_null\) then let __assign_(?P<b>\d+) = \(lowered : string\) in \(
    (?P=temp) := __assign_(?P=b);
    __assign_(?P=b)
  \) else let __assign_(?P<c>\d+) = \(name : string\) in \(
    (?P=temp) := __assign_(?P=c);
    __assign_(?P=c)
  \)\);
  let resolved = (?:mapGetRaw tyByIdent|mapGetRaw \(Obj\.repr tyByIdent\)|typedMapGet tyByIdent) \(!(?P=temp) : string\) in \(
    ignore \(if resolved == Obj\.magic \(HxRuntime\.hx_null\) then raise \(HxRuntime\.Hx_return \(Obj\.repr \("" : string\)\)\) else \(\)\);
    let t = Obj\.magic resolved in \(
      ignore \(if t == Obj\.magic \(HxRuntime\.hx_null\) then raise \(HxRuntime\.Hx_return \(Obj\.repr \("" : string\)\)\) else \(\)\);
      TyType\.toString \(Obj\.magic t\) \(\)
    \)
  \)
\) in Obj\.magic __fallback_result_(?P=result) with
  \| HxRuntime\.Hx_return __ret_(?P<ret>\d+) -> Obj\.obj __ret_(?P=ret) in let isIntExpr = ref""",
        re.S,
    )
    match = current_shape.search(src)
    if match is None:
        # Current bootstrap snapshots may already emit a different repaired tyForIdent shape.
        return

    current_replacement = f"""in let getTyIdentRaw = fun name -> let typedTyByIdent = Obj.magic tyByIdent in if typedTyByIdent == Obj.magic (HxRuntime.hx_null) then Obj.magic (HxRuntime.hx_null) else Obj.magic (HxMap.get_string typedTyByIdent name) in let resolveTyIdentName = fun name -> if getTyIdentRaw (name : string) != Obj.magic (HxRuntime.hx_null) then name else let lowered = (ocamlValueIdent (name : string) : string) in if not (HxString.equals lowered name) && getTyIdentRaw (lowered : string) != Obj.magic (HxRuntime.hx_null) then lowered else name in let tyForIdent = fun name -> try let __fallback_result_{match.group('result')} = let resolved = (getTyIdentRaw (resolveTyIdentName (name : string)) : Obj.t) in (
  ignore (if resolved == Obj.magic (HxRuntime.hx_null) then raise (HxRuntime.Hx_return (Obj.repr ("" : string))) else ());
  let t = Obj.magic resolved in (
    ignore (if t == Obj.magic (HxRuntime.hx_null) then raise (HxRuntime.Hx_return (Obj.repr ("" : string))) else ());
    TyType.toString (Obj.magic t) ()
  )
) in Obj.magic __fallback_result_{match.group('result')} with
  | HxRuntime.Hx_return __ret_{match.group('ret')} -> Obj.obj __ret_{match.group('ret')} in let isIntExpr = ref"""
    src = src[:match.start()] + current_replacement + src[match.end():]

    write_text(path_str, src)


def cmd_patch_negative_unop_is_int_expr(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-negative-unop-is-int-expr <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    if '| HxExpr.EUnop (_p0, _p1) -> let _g = (_p0 : string) in let _g1 = Obj.magic _p1 in if HxString.equals _g "-" then let inner = Obj.magic _g1 in let __assign_246a = (!isIntExpr) (Obj.magic inner)' in src:
        write_text(path_str, src)
        return

    if "let isIntExpr" not in src and "tyForIdent (name : string)" not in src:
        return

    old = '''| HxExpr.EInt _p0 -> (
        ignore _p0;
        let __assign_245 = true in (
          tempResult1 := __assign_245;
          __assign_245
        )
      )
      | HxExpr.EIdent _p0 -> let _g = (_p0 : string) in let name = (_g : string) in let __assign_246 = HxString.equals (tyForIdent (name : string)) "Int" in (
        tempResult1 := __assign_246;
        __assign_246
      )'''
    new = '''| HxExpr.EInt _p0 -> (
        ignore _p0;
        let __assign_245 = true in (
          tempResult1 := __assign_245;
          __assign_245
        )
      )
      | HxExpr.EUnop (_p0, _p1) -> let _g = (_p0 : string) in let _g1 = Obj.magic _p1 in if HxString.equals _g "-" then let inner = Obj.magic _g1 in let __assign_246a = (!isIntExpr) (Obj.magic inner) in (
        tempResult1 := __assign_246a;
        __assign_246a
      ) else let __assign_246b = false in (
        tempResult1 := __assign_246b;
        __assign_246b
      )
      | HxExpr.EIdent _p0 -> let _g = (_p0 : string) in let name = (_g : string) in let __assign_246 = HxString.equals (tyForIdent (name : string)) "Int" in (
        tempResult1 := __assign_246;
        __assign_246
      )'''
    if old in src:
        src = src.replace(old, new, 1)
        write_text(path_str, src)
        return

    current_shape = re.compile(
        r"""(?P<int_branch>\| HxExpr\.EInt _p0 -> \(\n"""
        r"""        ignore _p0;\n"""
        r"""        let __assign_\d+ = true in \(\n"""
        r"""          tempResult\d+ := __assign_\d+;\n"""
        r"""          __assign_\d+\n"""
        r"""        \)\n"""
        r"""      \)\n)"""
        r"""(?P<ident_branch>      \| HxExpr\.EIdent _p0 -> let _g = \(_p0 : string\) in let name = \(_g : string\) in let __assign_\d+ = HxString\.equals \(tyForIdent \(name : string\)\) "Int" in \(\n"""
        r"""        tempResult\d+ := __assign_\d+;\n"""
        r"""        __assign_\d+\n"""
        r"""      \))""",
        re.MULTILINE,
    )

    def repl(match: re.Match[str]) -> str:
        return (
            match.group("int_branch")
            + """      | HxExpr.EUnop (_p0, _p1) -> let _g = (_p0 : string) in let _g1 = Obj.magic _p1 in if HxString.equals _g "-" then let inner = Obj.magic _g1 in let __assign_bootstrap_neg_int = (!isIntExpr) (Obj.magic inner) in (
        tempResult2 := __assign_bootstrap_neg_int;
        __assign_bootstrap_neg_int
      ) else let __assign_bootstrap_neg_nonint = false in (
        tempResult2 := __assign_bootstrap_neg_nonint;
        __assign_bootstrap_neg_nonint
      )
"""
            + match.group("ident_branch")
        )

    src, count = current_shape.subn(repl, src, count=1)
    if count == 0:
        # Current bootstrap snapshots may already carry a different isIntExpr lowering shape.
        # Avoid failing the whole build-hxhx patch stack on this legacy exact-anchor repair.
        write_text(path_str, src)
        return
    write_text(path_str, src)


def cmd_patch_float_compare_unknown_numeric(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-float-compare-unknown-numeric <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    if "!isFloatExpr" not in src and "isUnknownNumericIdent" not in src:
        return

    replacements = [
        (
            '''| "!=" -> if (!isFloatExpr) (Obj.magic a) || (!isFloatExpr) (Obj.magic b) then''',
            '''| "!=" -> if (!isFloatExpr) (Obj.magic a) || (!isFloatExpr) (Obj.magic b) || (!isIntExpr) (Obj.magic a) && isUnknownNumericIdent (Obj.magic b) || (!isIntExpr) (Obj.magic b) && isUnknownNumericIdent (Obj.magic a) then''',
        ),
        (
            '''| "==" -> if (!isFloatExpr) (Obj.magic a) || (!isFloatExpr) (Obj.magic b) then''',
            '''| "==" -> if (!isFloatExpr) (Obj.magic a) || (!isFloatExpr) (Obj.magic b) || (!isIntExpr) (Obj.magic a) && isUnknownNumericIdent (Obj.magic b) || (!isIntExpr) (Obj.magic b) && isUnknownNumericIdent (Obj.magic a) then''',
        ),
        (
            '''| "<" | "<=" | ">" | ">=" -> if (!isFloatExpr) (Obj.magic a) || (!isFloatExpr) (Obj.magic b) then''',
            '''| "<" | "<=" | ">" | ">=" -> if (!isFloatExpr) (Obj.magic a) || (!isFloatExpr) (Obj.magic b) || (!isIntExpr) (Obj.magic a) && isUnknownNumericIdent (Obj.magic b) || (!isIntExpr) (Obj.magic b) && isUnknownNumericIdent (Obj.magic a) then''',
        ),
    ]
    patched_any = False
    for old, new in replacements:
        if old in src:
            src = src.replace(old, new)
            patched_any = True

    if not patched_any:
        write_text(path_str, src)
        return

    write_text(path_str, src)


def cmd_patch_int_compare_precedence(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-int-compare-precedence <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    if "isNegativeIntLikeExpr" not in src and "isUnknownNumericIdent" not in src:
        return

    if '''| "==" -> if (!isFloatExpr) (Obj.magic a) || (!isFloatExpr) (Obj.magic b) || (!isIntExpr) (Obj.magic a) && isUnknownNumericIdent (Obj.magic b) || (!isIntExpr) (Obj.magic b) && isUnknownNumericIdent (Obj.magic a) then''' in src:
        write_text(path_str, src)
        return

    if '''| "==" -> if (!isIntExpr) (Obj.magic a) && (!isFloatExpr) (Obj.magic a) && isNegativeIntLikeExpr (Obj.magic a)''' in src:
        write_text(path_str, src)
        return

    src = replace_one(
        src,
        '''| "==" -> if (!isFloatExpr) (Obj.magic a) || (!isFloatExpr) (Obj.magic b) || (!isIntExpr) (Obj.magic a) && isUnknownNumericIdent (Obj.magic b) || (!isIntExpr) (Obj.magic b) && isUnknownNumericIdent (Obj.magic a) || isNegativeIntLikeExpr (Obj.magic a) || isNegativeIntLikeExpr (Obj.magic b) then let __assign_45681 = (((("((" ^ HxString.toStdString ((!exprToOcamlAsFloat) (Obj.magic a))) ^ ") = (") ^ HxString.toStdString ((!exprToOcamlAsFloat) (Obj.magic b))) ^ "))" : string) in (''',
        '''| "==" -> if (!isIntExpr) (Obj.magic a) && (!isIntExpr) (Obj.magic b) then let __assign_45681 = (((("((" ^ HxString.toStdString la) ^ ") = (") ^ HxString.toStdString rb) ^ "))" : string) in (''',
        "build-hxhx: failed to locate bootstrap int-compare precedence == anchor in EmitterStage.ml\n",
    )
    src = replace_one(
        src,
        '''                              ) else let __assign_45682 = (((("((" ^ HxString.toStdString la) ^ ") = (") ^ HxString.toStdString rb) ^ "))" : string) in (''',
        '''                              ) else if (!isFloatExpr) (Obj.magic a) && isNegativeIntLikeExpr (Obj.magic a) || (!isFloatExpr) (Obj.magic b) && isNegativeIntLikeExpr (Obj.magic b) || (!isIntExpr) (Obj.magic a) && isUnknownNumericIdent (Obj.magic b) || (!isIntExpr) (Obj.magic b) && isUnknownNumericIdent (Obj.magic a) then let __assign_45683 = (((("((" ^ HxString.toStdString ((!exprToOcamlAsFloat) (Obj.magic a))) ^ ") = (") ^ HxString.toStdString ((!exprToOcamlAsFloat) (Obj.magic b))) ^ "))" : string) in (
                                tempResult13 := __assign_45683;
                                __assign_45683
                              ) else let __assign_45682 = (((("((" ^ HxString.toStdString la) ^ ") = (") ^ HxString.toStdString rb) ^ "))" : string) in (''',
        "build-hxhx: failed to locate bootstrap int-compare precedence == fallback anchor in EmitterStage.ml\n",
    )
    src = replace_one(
        src,
        '''| "<" | "<=" | ">" | ">=" -> if (!isFloatExpr) (Obj.magic a) || (!isFloatExpr) (Obj.magic b) || (!isIntExpr) (Obj.magic a) && isUnknownNumericIdent (Obj.magic b) || (!isIntExpr) (Obj.magic b) && isUnknownNumericIdent (Obj.magic a) || isNegativeIntLikeExpr (Obj.magic a) || isNegativeIntLikeExpr (Obj.magic b) then let __assign_45683 = (((((("((" ^ HxString.toStdString ((!exprToOcamlAsFloat) (Obj.magic a))) ^ ") ") ^ HxString.toStdString op) ^ " (") ^ HxString.toStdString ((!exprToOcamlAsFloat) (Obj.magic b))) ^ "))" : string) in (''',
        '''| "<" | "<=" | ">" | ">=" -> if (!isIntExpr) (Obj.magic a) && (!isIntExpr) (Obj.magic b) then let __assign_45683 = (((((("((" ^ HxString.toStdString la) ^ ") ") ^ HxString.toStdString op) ^ " (") ^ HxString.toStdString rb) ^ "))" : string) in (''',
        "build-hxhx: failed to locate bootstrap int-compare precedence ordering anchor in EmitterStage.ml\n",
    )
    src = replace_one(
        src,
        '''                              ) else let __assign_45684 = (((((("((" ^ HxString.toStdString la) ^ ") ") ^ HxString.toStdString op) ^ " (") ^ HxString.toStdString rb) ^ "))" : string) in (''',
        '''                              ) else if (!isFloatExpr) (Obj.magic a) && isNegativeIntLikeExpr (Obj.magic a) || (!isFloatExpr) (Obj.magic b) && isNegativeIntLikeExpr (Obj.magic b) || (!isIntExpr) (Obj.magic a) && isUnknownNumericIdent (Obj.magic b) || (!isIntExpr) (Obj.magic b) && isUnknownNumericIdent (Obj.magic a) then let __assign_45685 = (((((("((" ^ HxString.toStdString ((!exprToOcamlAsFloat) (Obj.magic a))) ^ ") ") ^ HxString.toStdString op) ^ " (") ^ HxString.toStdString ((!exprToOcamlAsFloat) (Obj.magic b))) ^ "))" : string) in (
                                tempResult13 := __assign_45685;
                                __assign_45685
                              ) else let __assign_45684 = (((((("((" ^ HxString.toStdString la) ^ ") ") ^ HxString.toStdString op) ^ " (") ^ HxString.toStdString rb) ^ "))" : string) in (''',
        "build-hxhx: failed to locate bootstrap int-compare precedence ordering fallback anchor in EmitterStage.ml\n",
    )

    write_text(path_str, src)


def cmd_patch_float_modulo_mutable_local(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-float-modulo-mutable-local <path>\n")
    path_str = argv[0]
    src = read_text(path_str)
    if '| "%="' not in src:
        return
    branch_rx = re.compile(
        r'\| "%=" -> let __assign_\d+ = Obj\.magic \(returnExprToOcaml \(Obj\.magic \(HxExpr\.EBinop \(\("%" : string\), Obj\.magic \(HxExpr\.EIdent \(name : string\)\), Obj\.magic rhs\)\)\) '
        r'(?P<allowed>allowedValueIdents(?:ForStmt)?) '
        r'\(Obj\.magic \(Obj\.magic \(HxRuntime\.hx_null\)\)\) \(Obj\.repr arityByIdent\) \(Obj\.repr tyCtx\) \(Obj\.repr staticImportByIdent\) '
        r'\(currentPackagePath : string\) \(Obj\.repr moduleNameByPkgAndClass\) \(Obj\.repr callSigByCallee\) : string\) in \(\n'
        r'\s*tempMaybeString := __assign_\d+;\n'
        r'\s*__assign_\d+\n'
        r'\s*\)',
        re.MULTILINE,
    )

    match = branch_rx.search(src)
    if match is None:
        return

    allowed = match.group("allowed")
    replacement = f'''| "%=" -> let hinted = ref (Obj.magic (HxRuntime.hx_null) : TyType.t) in (
                        ignore (let resolved = mapGetRaw (Obj.repr tyCtx) (name : string) in if resolved == Obj.magic (HxRuntime.hx_null) then let __assign_bootstrap_float_mod_hint_1 = Obj.magic (Obj.magic (HxMap.get_string localHints name)) in (
                          hinted := __assign_bootstrap_float_mod_hint_1;
                          __assign_bootstrap_float_mod_hint_1
                        ) else let __assign_bootstrap_float_mod_hint_2 = Obj.magic (Obj.magic resolved) in (
                          hinted := __assign_bootstrap_float_mod_hint_2;
                          __assign_bootstrap_float_mod_hint_2
                        ));
                        let rhsKind = ref (Obj.magic (HxRuntime.hx_null) : string) in (
                          ignore (match rhs with
                            | HxExpr.EFloat _ -> let __assign_bootstrap_rhs_kind_1 = ("Float" : string) in (
                              rhsKind := __assign_bootstrap_rhs_kind_1;
                              __assign_bootstrap_rhs_kind_1
                            )
                            | HxExpr.EInt _ -> let __assign_bootstrap_rhs_kind_2 = ("Int" : string) in (
                              rhsKind := __assign_bootstrap_rhs_kind_2;
                              __assign_bootstrap_rhs_kind_2
                            )
                            | HxExpr.EUnop (_p0, _p1) -> let _g_bootstrap_rhs_kind_1 = (_p0 : string) in let _g_bootstrap_rhs_kind_2 = Obj.magic _p1 in if HxString.equals _g_bootstrap_rhs_kind_1 "-" then let __assign_bootstrap_rhs_kind_unop = (match Obj.magic _g_bootstrap_rhs_kind_2 with
                              | HxExpr.EFloat _ -> ("Float" : string)
                              | HxExpr.EInt _ -> ("Int" : string)
                              | _ -> Obj.magic (HxRuntime.hx_null)) in (
                              rhsKind := __assign_bootstrap_rhs_kind_unop;
                              __assign_bootstrap_rhs_kind_unop
                            ) else let __assign_bootstrap_rhs_kind_00 = Obj.magic (HxRuntime.hx_null) in (
                              rhsKind := __assign_bootstrap_rhs_kind_00;
                              __assign_bootstrap_rhs_kind_00
                            )
                            | HxExpr.EIdent _p0 -> let _g_bootstrap_rhs_name = (_p0 : string) in let rhsName = (_g_bootstrap_rhs_name : string) in let rhsHint = ref (Obj.magic (HxRuntime.hx_null) : TyType.t) in (
                              ignore (let resolved = mapGetRaw (Obj.repr tyCtx) (rhsName : string) in if resolved == Obj.magic (HxRuntime.hx_null) then let __assign_bootstrap_rhs_hint_1 = Obj.magic (Obj.magic (HxMap.get_string localHints rhsName)) in (
                                rhsHint := __assign_bootstrap_rhs_hint_1;
                                __assign_bootstrap_rhs_hint_1
                              ) else let __assign_bootstrap_rhs_hint_2 = Obj.magic (Obj.magic resolved) in (
                                rhsHint := __assign_bootstrap_rhs_hint_2;
                                __assign_bootstrap_rhs_hint_2
                              ));
                              ignore (if !rhsHint != Obj.magic (HxRuntime.hx_null) && HxString.equals (TyType.toString (Obj.magic (!rhsHint)) ()) "Float" then let __assign_bootstrap_rhs_kind_5 = ("Float" : string) in (
                                rhsKind := __assign_bootstrap_rhs_kind_5;
                                __assign_bootstrap_rhs_kind_5
                              ) else if !rhsHint != Obj.magic (HxRuntime.hx_null) && HxString.equals (TyType.toString (Obj.magic (!rhsHint)) ()) "Int" then let __assign_bootstrap_rhs_kind_6 = ("Int" : string) in (
                                rhsKind := __assign_bootstrap_rhs_kind_6;
                                __assign_bootstrap_rhs_kind_6
                              ) else let __assign_bootstrap_rhs_kind_8 = Obj.magic (HxRuntime.hx_null) in (
                                rhsKind := __assign_bootstrap_rhs_kind_8;
                                __assign_bootstrap_rhs_kind_8
                              ));
                              let __assign_bootstrap_rhs_kind_9 = Obj.magic (HxRuntime.hx_null) in (
                                rhsKind := __assign_bootstrap_rhs_kind_9;
                                __assign_bootstrap_rhs_kind_9
                              )
                            )
                            | _ -> let __assign_bootstrap_rhs_kind_7 = Obj.magic (HxRuntime.hx_null) in (
                              rhsKind := __assign_bootstrap_rhs_kind_7;
                              __assign_bootstrap_rhs_kind_7
                            ));
                          if !hinted != Obj.magic (HxRuntime.hx_null) && HxString.equals (TyType.toString (Obj.magic (!hinted)) ()) "Float" && !rhsKind != Obj.magic (HxRuntime.hx_null) then let rhsRendered = (returnExprToOcaml (Obj.magic rhs) {allowed} (Obj.magic (Obj.magic (HxRuntime.hx_null))) (Obj.repr arityByIdent) (Obj.repr tyCtx) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee) : string) in let rhsFloat = if HxString.equals (!rhsKind) "Float" then (rhsRendered : string) else ("float_of_int (" ^ HxString.toStdString rhsRendered) ^ ")" in let __assign_bootstrap_float_modulo = (((("(mod_float (" ^ HxString.toStdString (ocamlReadValueIdent (name : string))) ^ ") (") ^ HxString.toStdString rhsFloat) ^ "))" : string) in (
                          tempMaybeString := __assign_bootstrap_float_modulo;
                          __assign_bootstrap_float_modulo
                        ) else let __assign_bootstrap_float_modulo = Obj.magic (returnExprToOcaml (Obj.magic (HxExpr.EBinop (("%" : string), Obj.magic (HxExpr.EIdent (name : string)), Obj.magic rhs))) {allowed} (Obj.magic (Obj.magic (HxRuntime.hx_null))) (Obj.repr arityByIdent) (Obj.repr tyCtx) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee) : string) in (
                          tempMaybeString := __assign_bootstrap_float_modulo;
                          __assign_bootstrap_float_modulo
                        ))
                      )'''

    src = src[:match.start()] + replacement + src[match.end():]

    write_text(path_str, src)


def cmd_patch_instance_call_receiver_forwarding(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-instance-call-receiver-forwarding <path>\n")
    path_str = argv[0]
    src = read_text(path_str)
    patched_any = False
    if "instanceCallName" not in src and "let renderedCall =" not in src:
        return

    old_nonzero_call = '''                                                                        ) else let renderedCall = ((HxString.toStdString c ^ " ") ^ HxString.toStdString (HxArray.join renderedArgs " " (fun x -> x)) : string) in if Obj.magic (!hx_sig) == Obj.magic (HxRuntime.hx_null) && StringTools.startsWith (c : string) ("Php_Global." : string) then let __assign_1498 = ((("(Obj.magic (" ^ HxString.toStdString renderedCall) ^ "))" : string)) in (
                                                                          tempResult13 := __assign_1498;
                                                                          __assign_1498
                                                                        ) else let __assign_1499 = (renderedCall : string) in (
                                                                          tempResult13 := __assign_1499;
                                                                          __assign_1499
                                                                        )'''
    new_nonzero_call = '''                                                                        ) else let tempBool_bootstrapImplicitThis = ref (false : bool) in (
                                                                          ignore (match callee with
                                                                            | HxExpr.EIdent _p0 -> ignore (let _g3 = (_p0 : string) in let name = (_g3 : string) in if Obj.magic (!hx_sig) == Obj.magic (HxRuntime.hx_null) && hasCurrentInstanceMethod (name : string) && HxString.equals c (ocamlValueIdent (name : string)) && (mapGetRaw (Obj.repr tyByIdent) ("this" : string) != Obj.magic (HxRuntime.hx_null) || mapGetRaw (Obj.repr tyByIdent) ("this_" : string) != Obj.magic (HxRuntime.hx_null)) then ignore (let tempLeft_bootstrapImplicitThis = ref (0 : int) in (
                                                                              ignore (let resolved = mapGetRaw (Obj.repr arityByIdent) (name : string) in if resolved == Obj.magic (HxRuntime.hx_null) then let __assign_bootstrap_implicit_this_arity = 0 in (
                                                                                tempLeft_bootstrapImplicitThis := __assign_bootstrap_implicit_this_arity;
                                                                                __assign_bootstrap_implicit_this_arity
                                                                              ) else let arity = resolved in let __assign_bootstrap_implicit_this_arity = arity in (
                                                                                tempLeft_bootstrapImplicitThis := __assign_bootstrap_implicit_this_arity;
                                                                                __assign_bootstrap_implicit_this_arity
                                                                              ));
                                                                              if hasCurrentInstanceMethod (name : string) then ignore (let __assign_bootstrap_implicit_this = true in (
                                                                                tempBool_bootstrapImplicitThis := __assign_bootstrap_implicit_this;
                                                                                __assign_bootstrap_implicit_this
                                                                              )) else ignore ()
                                                                            )) else ignore ())
                                                                            | _ -> ignore ());
                                                                          let renderedCall = if !tempBool_bootstrapImplicitThis then (((HxString.toStdString c ^ " (this_) ") ^ HxString.toStdString (HxArray.join renderedArgs " " (fun x -> x))) : string) else ((HxString.toStdString c ^ " ") ^ HxString.toStdString (HxArray.join renderedArgs " " (fun x -> x)) : string) in if Obj.magic (!hx_sig) == Obj.magic (HxRuntime.hx_null) && StringTools.startsWith (c : string) ("Php_Global." : string) then let __assign_1498 = ((("(Obj.magic (" ^ HxString.toStdString renderedCall) ^ "))" : string)) in (
                                                                            tempResult13 := __assign_1498;
                                                                            __assign_1498
                                                                          ) else let __assign_1499 = (renderedCall : string) in (
                                                                            tempResult13 := __assign_1499;
                                                                            __assign_1499
                                                                          )
                                                                        )'''

    old_nonzero_call_late = '''                                                                        ) else let renderedCall = ((HxString.toStdString c ^ " ") ^ HxString.toStdString (HxArray.join renderedArgs " " (fun x -> x)) : string) in if Obj.magic (!hx_sig) == Obj.magic (HxRuntime.hx_null) && StringTools.startsWith (c : string) ("Php_Global." : string) then let __assign_1829 = ((("(Obj.magic (" ^ HxString.toStdString renderedCall) ^ "))" : string)) in (
                                                                          tempResult13 := __assign_1829;
                                                                          __assign_1829
                                                                        ) else let __assign_1830 = (renderedCall : string) in (
                                                                          tempResult13 := __assign_1830;
                                                                          __assign_1830
                                                                        )'''
    new_nonzero_call_late = '''                                                                        ) else let tempBool_bootstrapImplicitThis = ref (false : bool) in (
                                                                          ignore (match callee with
                                                                            | HxExpr.EIdent _p0 -> ignore (let _g3 = (_p0 : string) in let name = (_g3 : string) in if Obj.magic (!hx_sig) == Obj.magic (HxRuntime.hx_null) && hasCurrentInstanceMethod (name : string) && HxString.equals c (ocamlValueIdent (name : string)) && (mapGetRaw (Obj.repr tyByIdent) ("this" : string) != Obj.magic (HxRuntime.hx_null) || mapGetRaw (Obj.repr tyByIdent) ("this_" : string) != Obj.magic (HxRuntime.hx_null)) then ignore (let tempLeft_bootstrapImplicitThis = ref (0 : int) in (
                                                                              ignore (let resolved = mapGetRaw (Obj.repr arityByIdent) (name : string) in if resolved == Obj.magic (HxRuntime.hx_null) then let __assign_bootstrap_implicit_this_arity = 0 in (
                                                                                tempLeft_bootstrapImplicitThis := __assign_bootstrap_implicit_this_arity;
                                                                                __assign_bootstrap_implicit_this_arity
                                                                              ) else let arity = resolved in let __assign_bootstrap_implicit_this_arity = arity in (
                                                                                tempLeft_bootstrapImplicitThis := __assign_bootstrap_implicit_this_arity;
                                                                                __assign_bootstrap_implicit_this_arity
                                                                              ));
                                                                              if hasCurrentInstanceMethod (name : string) then ignore (let __assign_bootstrap_implicit_this = true in (
                                                                                tempBool_bootstrapImplicitThis := __assign_bootstrap_implicit_this;
                                                                                __assign_bootstrap_implicit_this
                                                                              )) else ignore ()
                                                                            )) else ignore ())
                                                                            | _ -> ignore ());
                                                                          let renderedCall = if !tempBool_bootstrapImplicitThis then (((HxString.toStdString c ^ " (this_) ") ^ HxString.toStdString (HxArray.join renderedArgs " " (fun x -> x))) : string) else ((HxString.toStdString c ^ " ") ^ HxString.toStdString (HxArray.join renderedArgs " " (fun x -> x)) : string) in if Obj.magic (!hx_sig) == Obj.magic (HxRuntime.hx_null) && StringTools.startsWith (c : string) ("Php_Global." : string) then let __assign_1829 = ((("(Obj.magic (" ^ HxString.toStdString renderedCall) ^ "))" : string)) in (
                                                                            tempResult13 := __assign_1829;
                                                                            __assign_1829
                                                                          ) else let __assign_1830 = (renderedCall : string) in (
                                                                            tempResult13 := __assign_1830;
                                                                            __assign_1830
                                                                          )
                                                                        )'''

    if old_nonzero_call in src:
        src = src.replace(old_nonzero_call, new_nonzero_call, 1)
        patched_any = True
    if old_nonzero_call_late in src:
        src = src.replace(old_nonzero_call_late, new_nonzero_call_late, 1)
        patched_any = True

    plain_nonzero_pattern = re.compile(
        r'(?P<indent>\s*)\) else let renderedCall = \(\(HxString\.toStdString c \^ " "\) \^ HxString\.toStdString \(HxArray\.join renderedArgs " " \(fun x -> x\)\) : string\) in if Obj\.magic \(!hx_sig\) == Obj\.magic \(HxRuntime\.hx_null\) && StringTools\.startsWith \(c : string\) \("Php_Global\." : string\) then let '
    )

    def rewrite_plain_nonzero(match: re.Match) -> str:
        indent = match.group("indent")
        return (
            indent
            + ') else let renderedCall = if Obj.magic (!hx_sig) == Obj.magic (HxRuntime.hx_null) && ((match callee with | HxExpr.EIdent _p0 -> let _g3 = (_p0 : string) in let name = (_g3 : string) in hasCurrentInstanceMethod (name : string) && HxString.equals c (ocamlValueIdent (name : string)) && (mapGetRaw (Obj.repr tyByIdent) ("this" : string) != Obj.magic (HxRuntime.hx_null) || mapGetRaw (Obj.repr tyByIdent) ("this_" : string) != Obj.magic (HxRuntime.hx_null) || hasAllowedValueIdent ("this" : string) || hasAllowedValueIdent ("this_" : string)) | _ -> false) : bool) then (((HxString.toStdString c ^ " (this_) ") ^ HxString.toStdString (HxArray.join renderedArgs " " (fun x -> x))) : string) else ((HxString.toStdString c ^ " ") ^ HxString.toStdString (HxArray.join renderedArgs " " (fun x -> x)) : string) in if Obj.magic (!hx_sig) == Obj.magic (HxRuntime.hx_null) && StringTools.startsWith (c : string) ("Php_Global." : string) then let '
        )

    src, regex_nonzero_count = plain_nonzero_pattern.subn(rewrite_plain_nonzero, src)
    patched_any = patched_any or regex_nonzero_count > 0

    src, rendered_args_implicit_this_count = re.subn(
        r'mapHasRaw \(Obj\.repr arityByIdent\) \(name : string\) && HxString\.equals c \(ocamlValueIdent \(name : string\)\) && (\(mapGetRaw \(Obj\.repr tyByIdent\) \("this" : string\) != Obj\.magic \(HxRuntime\.hx_null\) \|\| mapGetRaw \(Obj\.repr tyByIdent\) \("this_" : string\) != Obj\.magic \(HxRuntime\.hx_null\) \|\| hasAllowedValueIdent \("this" : string\) \|\| hasAllowedValueIdent \("this_" : string\)\)) && let resolved = mapGetRaw \(Obj\.repr arityByIdent\) \(name : string\) in let arity = if resolved == Obj\.magic \(HxRuntime\.hx_null\) then 0 else \(Obj\.magic resolved : int\) in HxArray\.length renderedArgs = arity',
        r'hasCurrentInstanceMethod (name : string) && HxString.equals c (ocamlValueIdent (name : string)) && \1',
        src,
    )
    patched_any = patched_any or rendered_args_implicit_this_count > 0

    src, implicit_this_count = re.subn(
        r'mapHasRaw \(Obj\.repr arityByIdent\) \(name : string\) && HxInt\.add \(HxArray\.length args\) 1 = (!tempRight\d+)',
        r'mapHasRaw (Obj.repr arityByIdent) (name : string) && HxArray.length args = \1',
        src,
    )
    patched_any = patched_any or implicit_this_count > 0

    if not patched_any:
        fail("build-hxhx: failed to locate bootstrap nonzero instance-call emission branch\n")

    write_text(path_str, src + "\n(* hxhx(stage3) bootstrap shim: instance call receiver forwarding repair *)\n")


def cmd_patch_instance_call_this_binding(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-instance-call-this-binding <path>\n")
    path_str = argv[0]
    src = read_text(path_str)
    patched_any = False
    if "instanceCallName" not in src:
        return
    if 'hasAllowedValueIdent ("this" : string)' in src and 'hasAllowedValueIdent ("this_" : string)' in src:
        # Current bootstrap snapshots already carry the this/this_ allowed-ident guard
        # in the recovered instance-call path.
        return

    old_this_binding_early = '''                                            if mapGetRaw (Obj.repr tyByIdent) (!tempString22 : string) != Obj.magic (HxRuntime.hx_null) || mapGetRaw (Obj.repr tyByIdent) (!tempString23 : string) != Obj.magic (HxRuntime.hx_null) then let __assign_1343 = (HxString.toStdString (ocamlValueIdent (instanceCallName : string)) ^ " (this_)" : string) in (
                                              tempString21 := __assign_1343;
                                              __assign_1343
                                            ) else let __assign_1344 = (ocamlValueIdent (instanceCallName : string) : string) in (
                                              tempString21 := __assign_1344;
                                              __assign_1344
                                            )'''
    new_this_binding_early = '''                                            if mapGetRaw (Obj.repr tyByIdent) (!tempString22 : string) != Obj.magic (HxRuntime.hx_null) || mapGetRaw (Obj.repr tyByIdent) (!tempString23 : string) != Obj.magic (HxRuntime.hx_null) || hasAllowedValueIdent ("this" : string) || hasAllowedValueIdent ("this_" : string) then let __assign_1343 = (HxString.toStdString (ocamlValueIdent (instanceCallName : string)) ^ " (this_)" : string) in (
                                              tempString21 := __assign_1343;
                                              __assign_1343
                                            ) else let __assign_1344 = (ocamlValueIdent (instanceCallName : string) : string) in (
                                              tempString21 := __assign_1344;
                                              __assign_1344
                                            )'''

    old_this_binding_late = '''                                            if mapGetRaw (Obj.repr tyByIdent) (!tempString44 : string) != Obj.magic (HxRuntime.hx_null) || mapGetRaw (Obj.repr tyByIdent) (!tempString45 : string) != Obj.magic (HxRuntime.hx_null) then let __assign_1674 = (HxString.toStdString (ocamlValueIdent (instanceCallName : string)) ^ " (this_)" : string) in (
                                              tempString43 := __assign_1674;
                                              __assign_1674
                                            ) else let __assign_1675 = (ocamlValueIdent (instanceCallName : string) : string) in (
                                              tempString43 := __assign_1675;
                                              __assign_1675
                                            )'''
    new_this_binding_late = '''                                            if mapGetRaw (Obj.repr tyByIdent) (!tempString44 : string) != Obj.magic (HxRuntime.hx_null) || mapGetRaw (Obj.repr tyByIdent) (!tempString45 : string) != Obj.magic (HxRuntime.hx_null) || hasAllowedValueIdent ("this" : string) || hasAllowedValueIdent ("this_" : string) then let __assign_1674 = (HxString.toStdString (ocamlValueIdent (instanceCallName : string)) ^ " (this_)" : string) in (
                                              tempString43 := __assign_1674;
                                              __assign_1674
                                            ) else let __assign_1675 = (ocamlValueIdent (instanceCallName : string) : string) in (
                                              tempString43 := __assign_1675;
                                              __assign_1675
                                            )'''

    if old_this_binding_early in src:
        src = src.replace(old_this_binding_early, new_this_binding_early, 1)
        patched_any = True
    if old_this_binding_late in src:
        src = src.replace(old_this_binding_late, new_this_binding_late, 1)
        patched_any = True

    src, regex_this_binding_count = re.subn(
        r'if mapGetRaw \(Obj\.repr tyByIdent\) \(!(?P<left>tempString\d+) : string\) != Obj\.magic \(HxRuntime\.hx_null\) \|\| mapGetRaw \(Obj\.repr tyByIdent\) \(!(?P<right>tempString\d+) : string\) != Obj\.magic \(HxRuntime\.hx_null\) then let ',
        lambda m: (
            'if mapGetRaw (Obj.repr tyByIdent) (!' + m.group('left') + ' : string) != Obj.magic (HxRuntime.hx_null) || mapGetRaw (Obj.repr tyByIdent) (!' + m.group('right') + ' : string) != Obj.magic (HxRuntime.hx_null) || hasAllowedValueIdent ("this" : string) || hasAllowedValueIdent ("this_" : string) then let '
        ),
        src,
    )
    patched_any = patched_any or regex_this_binding_count > 0

    if not patched_any:
        return

    write_text(path_str, src + "\n(* hxhx(stage3) bootstrap shim: instance call this-binding repair *)\n")


def cmd_patch_instance_method_value_binding(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-instance-method-value-binding <path>\n")
    path_str = argv[0]
    src = read_text(path_str)
    if "hasCurrentInstanceMethod" not in src:
        return
    if (
        'hasCurrentInstanceMethod (name : string) && (typedMapGet tyByIdent' in src
        and 'hasAllowedValueIdent ("this" : string)' in src
        and 'hasAllowedValueIdent ("this_" : string)' in src
    ):
        write_text(path_str, src)
        return

    old = '''                            if hasCurrentInstanceMethod (name : string) && (mapGetRaw (Obj.repr tyByIdent) (!tempString3 : string) != Obj.magic (HxRuntime.hx_null) || mapGetRaw (Obj.repr tyByIdent) (!tempString4 : string) != Obj.magic (HxRuntime.hx_null)) then let __assign_395 = (HxString.toStdString (ocamlValueIdent (name : string)) ^ " (this_)" : string) in (
                              tempResult13 := __assign_395;
                              __assign_395
                            )'''
    new = '''                            if hasCurrentInstanceMethod (name : string) && (mapGetRaw (Obj.repr tyByIdent) (!tempString3 : string) != Obj.magic (HxRuntime.hx_null) || mapGetRaw (Obj.repr tyByIdent) (!tempString4 : string) != Obj.magic (HxRuntime.hx_null) || hasAllowedValueIdent ("this" : string) || hasAllowedValueIdent ("this_" : string)) then let __assign_395 = (HxString.toStdString (ocamlValueIdent (name : string)) ^ " (this_)" : string) in (
                              tempResult13 := __assign_395;
                              __assign_395
                            )'''

    if old in src:
        src = src.replace(old, new, 1)
        write_text(path_str, src + "\n(* hxhx(stage3) bootstrap shim: instance-method value binding repair *)\n")
        return

    src, count = re.subn(
        r'if hasCurrentInstanceMethod \(name : string\) && \(typedMapGet tyByIdent \(!(?P<left>tempString\d+) : string\) != Obj\.magic \(HxRuntime\.hx_null\) \|\| typedMapGet tyByIdent \(!(?P<right>tempString\d+) : string\) != Obj\.magic \(HxRuntime\.hx_null\)\) then let ',
        lambda m: (
            'if hasCurrentInstanceMethod (name : string) && (typedMapGet tyByIdent (!'
            + m.group('left')
            + ' : string) != Obj.magic (HxRuntime.hx_null) || typedMapGet tyByIdent (!'
            + m.group('right')
            + ' : string) != Obj.magic (HxRuntime.hx_null) || hasAllowedValueIdent ("this" : string) || hasAllowedValueIdent ("this_" : string)) then let '
        ),
        src,
        count=1,
    )
    if count == 0:
        write_text(path_str, src)
        return
    write_text(path_str, src + "\n(* hxhx(stage3) bootstrap shim: instance-method value binding repair *)\n")


def cmd_patch_instance_call_preapplied_arity(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-instance-call-preapplied-arity <path>\n")
    path_str = argv[0]
    src = read_text(path_str)
    patched_any = False
    if "receiverPreApplied" not in src and "preAppliedArgCount" not in src and "instanceCallName" not in src:
        return
    current_module_name_expr = (
        'let currentModuleNameForArity = (if !currentOcamlModuleName != Obj.magic (HxRuntime.hx_null) then (!currentOcamlModuleName : string) '
        'else (currentModuleShortNameForStage3 currentPackagePath : string) : string) in '
    )

    src, receiver_count = re.subn(
        r'let receiverPreApplied = HxString\.indexOf c " \(this_\)" 0 <> -1 in let callSigForExpr = fun expr ->',
        'let receiverPreApplied = HxString.indexOf c " (this_)" 0 <> -1 in let preAppliedArgCount = if receiverPreApplied then 1 else 0 in let callSigForExpr = fun expr ->',
        src,
    )
    patched_any = patched_any or receiver_count > 0

    src, ident_lookup_count = re.subn(
        r'let byLowered = Obj\.magic \(!tempMaybeEmitterCallSig\) in if byLowered != Obj\.magic \(HxRuntime\.hx_null\) then let __assign_(?P<assign_lowered>\d+) = Obj\.magic byLowered in \(\s*tempResult18 := __assign_(?P=assign_lowered);\s*__assign_(?P=assign_lowered)\s*\) else let resolved = mapGetRaw \(Obj\.repr callSigByCallee\) \(name : string\) in if resolved == Obj\.magic \(HxRuntime\.hx_null\) then let __assign_(?P<assign_none>\d+) = Obj\.magic \(HxRuntime\.hx_null\) in \(\s*tempResult18 := __assign_(?P=assign_none);\s*__assign_(?P=assign_none)\s*\) else let __assign_(?P<assign_name>\d+) = Obj\.magic resolved in \(\s*tempResult18 := __assign_(?P=assign_name);\s*__assign_(?P=assign_name)\s*\)',
        current_module_name_expr + r'let byLowered = Obj.magic (!tempMaybeEmitterCallSig) in if byLowered != Obj.magic (HxRuntime.hx_null) then let __assign_\g<assign_lowered> = Obj.magic byLowered in (\n                                                              tempResult18 := __assign_\g<assign_lowered>;\n                                                              __assign_\g<assign_lowered>\n                                                            ) else let resolved = mapGetRaw (Obj.repr callSigByCallee) (name : string) in if resolved != Obj.magic (HxRuntime.hx_null) then let __assign_\g<assign_name> = Obj.magic resolved in (\n                                                              tempResult18 := __assign_\g<assign_name>;\n                                                              __assign_\g<assign_name>\n                                                            ) else if String.length currentModuleNameForArity > 0 then let qualifiedLowered = ((currentModuleNameForArity) ^ "." ^ lowered : string) in let resolvedQualifiedLowered = mapGetRaw (Obj.repr callSigByCallee) (qualifiedLowered : string) in if resolvedQualifiedLowered != Obj.magic (HxRuntime.hx_null) then let __assign_\g<assign_none> = Obj.magic resolvedQualifiedLowered in (\n                                                              tempResult18 := __assign_\g<assign_none>;\n                                                              __assign_\g<assign_none>\n                                                            ) else let qualifiedName = ((currentModuleNameForArity) ^ "." ^ name : string) in let resolvedQualifiedName = mapGetRaw (Obj.repr callSigByCallee) (qualifiedName : string) in if resolvedQualifiedName == Obj.magic (HxRuntime.hx_null) then let __assign_\g<assign_none> = Obj.magic (HxRuntime.hx_null) in (\n                                                              tempResult18 := __assign_\g<assign_none>;\n                                                              __assign_\g<assign_none>\n                                                            ) else let __assign_\g<assign_none> = Obj.magic resolvedQualifiedName in (\n                                                              tempResult18 := __assign_\g<assign_none>;\n                                                              __assign_\g<assign_none>\n                                                            ) else let __assign_\g<assign_none> = Obj.magic (HxRuntime.hx_null) in (\n                                                              tempResult18 := __assign_\g<assign_none>;\n                                                              __assign_\g<assign_none>\n                                                            )',
        src,
    )
    patched_any = patched_any or ident_lookup_count > 0

    src, field_lookup_count = re.subn(
        r'let byLowered = Obj\.magic \(!tempMaybeEmitterCallSig1\) in if byLowered != Obj\.magic \(HxRuntime\.hx_null\) then let __assign_(?P<assign_lowered>\d+) = Obj\.magic byLowered in \(\s*tempResult18 := __assign_(?P=assign_lowered);\s*__assign_(?P=assign_lowered)\s*\) else let resolved = mapGetRaw \(Obj\.repr callSigByCallee\) \(name : string\) in if resolved == Obj\.magic \(HxRuntime\.hx_null\) then let __assign_(?P<assign_none>\d+) = Obj\.magic \(HxRuntime\.hx_null\) in \(\s*tempResult18 := __assign_(?P=assign_none);\s*__assign_(?P=assign_none)\s*\) else let __assign_(?P<assign_name>\d+) = Obj\.magic resolved in \(\s*tempResult18 := __assign_(?P=assign_name);\s*__assign_(?P=assign_name)\s*\)',
        current_module_name_expr + r'let byLowered = Obj.magic (!tempMaybeEmitterCallSig1) in if byLowered != Obj.magic (HxRuntime.hx_null) then let __assign_\g<assign_lowered> = Obj.magic byLowered in (\n                                                              tempResult18 := __assign_\g<assign_lowered>;\n                                                              __assign_\g<assign_lowered>\n                                                            ) else let resolved = mapGetRaw (Obj.repr callSigByCallee) (name : string) in if resolved != Obj.magic (HxRuntime.hx_null) then let __assign_\g<assign_name> = Obj.magic resolved in (\n                                                              tempResult18 := __assign_\g<assign_name>;\n                                                              __assign_\g<assign_name>\n                                                            ) else if String.length currentModuleNameForArity > 0 then let qualifiedLowered = ((currentModuleNameForArity) ^ "." ^ lowered : string) in let resolvedQualifiedLowered = mapGetRaw (Obj.repr callSigByCallee) (qualifiedLowered : string) in if resolvedQualifiedLowered != Obj.magic (HxRuntime.hx_null) then let __assign_\g<assign_none> = Obj.magic resolvedQualifiedLowered in (\n                                                              tempResult18 := __assign_\g<assign_none>;\n                                                              __assign_\g<assign_none>\n                                                            ) else let qualifiedName = ((currentModuleNameForArity) ^ "." ^ name : string) in let resolvedQualifiedName = mapGetRaw (Obj.repr callSigByCallee) (qualifiedName : string) in if resolvedQualifiedName == Obj.magic (HxRuntime.hx_null) then let __assign_\g<assign_none> = Obj.magic (HxRuntime.hx_null) in (\n                                                              tempResult18 := __assign_\g<assign_none>;\n                                                              __assign_\g<assign_none>\n                                                            ) else let __assign_\g<assign_none> = Obj.magic resolvedQualifiedName in (\n                                                              tempResult18 := __assign_\g<assign_none>;\n                                                              __assign_\g<assign_none>\n                                                            ) else let __assign_\g<assign_none> = Obj.magic (HxRuntime.hx_null) in (\n                                                              tempResult18 := __assign_\g<assign_none>;\n                                                              __assign_\g<assign_none>\n                                                            )',
        src,
    )
    patched_any = patched_any or field_lookup_count > 0

    src, overapply_sig_count = re.subn(
        r'HxArray\.length args > Obj\.obj \(HxAnon\.get \(Obj\.magic \(!hx_sig\)\) "expected"\)',
        r'HxInt.add (HxArray.length args) preAppliedArgCount > Obj.obj (HxAnon.get (Obj.magic (!hx_sig)) "expected")',
        src,
    )
    patched_any = patched_any or overapply_sig_count > 0

    src, overapply_arity_count = re.subn(
        r'mapHasRaw \(Obj\.repr arityByIdent\) \(c : string\) && HxArray\.length args > !(?P<arity>tempRight\d+)',
        r'mapHasRaw (Obj.repr arityByIdent) (c : string) && HxInt.add (HxArray.length args) preAppliedArgCount > !\g<arity>',
        src,
    )
    patched_any = patched_any or overapply_arity_count > 0

    src, missing_count = re.subn(
        r'let expected = Obj\.obj \(HxAnon\.get \(Obj\.magic \(!hx_sig\)\) "expected"\) in if expected > HxArray\.length \(!fullArgs\) then ignore \(let __assign_(?P<assign>\d+) = HxInt\.sub expected \(HxArray\.length \(!fullArgs\)\) in \(',
        r'let expectedAfterPreapply = HxInt.sub (Obj.obj (HxAnon.get (Obj.magic (!hx_sig)) "expected")) preAppliedArgCount in if expectedAfterPreapply > HxArray.length (!fullArgs) then ignore (let __assign_\g<assign> = HxInt.sub expectedAfterPreapply (HxArray.length (!fullArgs)) in (',
        src,
    )
    patched_any = patched_any or missing_count > 0

    src, instance_arity_fallback_count = re.subn(
        r'ignore \(if !missingCount = 0 && Obj\.magic \(!hx_sig\) != Obj\.magic \(HxRuntime\.hx_null\) then ignore \(let expectedAfterPreapply = HxInt\.sub \(Obj\.obj \(HxAnon\.get \(Obj\.magic \(!hx_sig\)\) "expected"\)\) preAppliedArgCount in if expectedAfterPreapply > HxArray\.length \(!fullArgs\) then ignore \(let __assign_(?P<assign>\d+) = HxInt\.sub expectedAfterPreapply \(HxArray\.length \(!fullArgs\)\) in \(\s*missingCount := __assign_(?P=assign);\s*__assign_(?P=assign)\s*\)\) else \(\)\) else \(\)\);',
        r'ignore (if !missingCount = 0 && Obj.magic (!hx_sig) != Obj.magic (HxRuntime.hx_null) then ignore (let expectedAfterPreapply = HxInt.sub (Obj.obj (HxAnon.get (Obj.magic (!hx_sig)) "expected")) preAppliedArgCount in if expectedAfterPreapply > HxArray.length (!fullArgs) then ignore (let __assign_\g<assign> = HxInt.sub expectedAfterPreapply (HxArray.length (!fullArgs)) in (\n                                                                    missingCount := __assign_\g<assign>;\n                                                                    __assign_\g<assign>\n                                                                  )) else ()) else ()); ignore (if !missingCount = 0 && Obj.magic (!hx_sig) == Obj.magic (HxRuntime.hx_null) && instanceCallName != Obj.magic (HxRuntime.hx_null) && mapHasRaw (Obj.repr arityByIdent) (instanceCallName : string) then ignore (let expectedByArity = Obj.obj (mapGetRaw (Obj.repr arityByIdent) (instanceCallName : string)) in if expectedByArity > HxArray.length (!fullArgs) then ignore (let __assign_instance_arity = HxInt.sub expectedByArity (HxArray.length (!fullArgs)) in (\n                                                                    missingCount := __assign_instance_arity;\n                                                                    __assign_instance_arity\n                                                                  )) else ()) else ());',
        src,
    )
    patched_any = patched_any or instance_arity_fallback_count > 0

    src, trailing_pos_count = re.subn(
        r'Obj\.obj \(HxAnon\.get \(Obj\.magic \(!hx_sig\)\) "expected"\) > HxArray\.length \(!fullArgs\)',
        r'HxInt.sub (Obj.obj (HxAnon.get (Obj.magic (!hx_sig)) "expected")) preAppliedArgCount > HxArray.length (!fullArgs)',
        src,
    )
    patched_any = patched_any or trailing_pos_count > 0

    src, missing_before_count = re.subn(
        r'let missingBefore = HxInt\.sub \(Obj\.obj \(HxAnon\.get \(Obj\.magic \(!hx_sig\)\) "expected"\)\) \(HxArray\.length \(!fullArgs\)\) in',
        r'let missingBefore = HxInt.sub (HxInt.sub (Obj.obj (HxAnon.get (Obj.magic (!hx_sig)) "expected")) preAppliedArgCount) (HxArray.length (!fullArgs)) in',
        src,
    )
    patched_any = patched_any or missing_before_count > 0

    src, implicit_this_ident_count = re.subn(
        r'let __assign_(?P<assign>\d+) = \((?P<prefix>\(mapGetRaw \(Obj\.repr tyByIdent\) \(!tempString\d+ : string\) != Obj\.magic \(HxRuntime\.hx_null\) \|\| mapGetRaw \(Obj\.repr tyByIdent\) \(!tempString\d+ : string\) != Obj\.magic \(HxRuntime\.hx_null\)\)) && mapHasRaw \(Obj\.repr arityByIdent\) \(name : string\) && HxArray\.length args = !\s*(?P<arity>tempRight\d+)\) in',
        r'let __assign_\g<assign> = (not (receiverPreApplied) && \g<prefix> && mapHasRaw (Obj.repr arityByIdent) (name : string) && HxInt.add (HxArray.length args) 1 = !\g<arity>) in',
        src,
    )
    patched_any = patched_any or implicit_this_ident_count > 0

    src, implicit_this_field_count = re.subn(
        r'let __assign_(?P<assign>\d+) = mapHasRaw \(Obj\.repr arityByIdent\) \(name : string\) && HxArray\.length args = !\s*(?P<arity>tempRight\d+) in',
        r'let __assign_\g<assign> = not (receiverPreApplied) && mapHasRaw (Obj.repr arityByIdent) (name : string) && HxInt.add (HxArray.length args) 1 = !\g<arity> in',
        src,
    )
    patched_any = patched_any or implicit_this_field_count > 0

    src, receiver_insert_count = re.subn(
        r'if Obj\.magic \(!hx_sig\) != Obj\.magic \(HxRuntime\.hx_null\) && HxRuntime\.unbox_bool_or_obj \(HxAnon\.get \(Obj\.magic \(!hx_sig\)\) "needsReceiver"\) && HxArray\.length \(!fullArgs\) < Obj\.obj \(HxAnon\.get \(Obj\.magic \(!hx_sig\)\) "required"\) then',
        r'if not (receiverPreApplied) && Obj.magic (!hx_sig) != Obj.magic (HxRuntime.hx_null) && HxRuntime.unbox_bool_or_obj (HxAnon.get (Obj.magic (!hx_sig)) "needsReceiver") && HxArray.length (!fullArgs) < Obj.obj (HxAnon.get (Obj.magic (!hx_sig)) "required") then',
        src,
    )
    patched_any = patched_any or receiver_insert_count > 0

    src, nullary_preapplied_count = re.subn(
        r'let missingCount = ref missing in \(',
        'let missingCount = ref (if receiverPreApplied && Obj.magic (!hx_sig) != Obj.magic (HxRuntime.hx_null) && Obj.obj (HxAnon.get (Obj.magic (!hx_sig)) "expected") = preAppliedArgCount then 0 else missing) in (',
        src,
    )
    patched_any = patched_any or nullary_preapplied_count > 0

    src, append_unit_ident_count = re.subn(
        r'if hasCurrentInstanceMethod \(name : string\) && \(mapGetRaw \(Obj\.repr tyByIdent\) \(!(?P<this_name>tempString\d+) : string\) != Obj\.magic \(HxRuntime\.hx_null\) \|\| mapGetRaw \(Obj\.repr tyByIdent\) \(!(?P<this_alt>tempString\d+) : string\) != Obj\.magic \(HxRuntime\.hx_null\)\) && !(?P<arity>tempLeft\d+) <= 1 then ignore \(let __assign_(?P<assign>\d+) = false in \(',
        r'if hasCurrentInstanceMethod (name : string) && (receiverPreApplied || (mapGetRaw (Obj.repr tyByIdent) (!\g<this_name> : string) != Obj.magic (HxRuntime.hx_null) || mapGetRaw (Obj.repr tyByIdent) (!\g<this_alt> : string) != Obj.magic (HxRuntime.hx_null))) && (!\g<arity> <= 1 || receiverPreApplied) then ignore (let __assign_\g<assign> = false in (',
        src,
    )
    patched_any = patched_any or append_unit_ident_count > 0

    src, append_unit_this_field_count = re.subn(
        r'if !\s*(?P<arity>tempLeft\d+) <= 1 then ignore \(let __assign_(?P<assign>\d+) = false in \(',
        r'if !\g<arity> <= 1 || receiverPreApplied then ignore (let __assign_\g<assign> = false in (',
        src,
        count=1,
    )
    patched_any = patched_any or append_unit_this_field_count > 0

    src, append_unit_render_count = re.subn(
        r'ignore \(if !appendUnit then let __assign_(?P<assign_true>\d+) = \(HxString\.toStdString c \^ " \(\)" : string\) in \(\s*'
        r'(?P<temp_true>tempString\d+) := __assign_(?P=assign_true);\s*'
        r'__assign_(?P=assign_true)\s*\) else let __assign_(?P<assign_false>\d+) = \(c : string\) in \(\s*'
        r'(?P<temp_false>tempString\d+) := __assign_(?P=assign_false);\s*'
        r'__assign_(?P=assign_false)\s*\)\);',
        r'ignore (if receiverPreApplied then let __assign_\g<assign_false> = (c : string) in ('
        r'\g<temp_false> := __assign_\g<assign_false>;'
        r'__assign_\g<assign_false>'
        r') else if !appendUnit then let __assign_\g<assign_true> = (HxString.toStdString c ^ " ()" : string) in ('
        r'\g<temp_true> := __assign_\g<assign_true>;'
        r'__assign_\g<assign_true>'
        r') else let __assign_\g<assign_false> = (c : string) in ('
        r'\g<temp_false> := __assign_\g<assign_false>;'
        r'__assign_\g<assign_false>'
        r'));',
        src,
    )
    patched_any = patched_any or append_unit_render_count > 0

    src, final_preapplied_padding_count = re.subn(
        r'ignore \(let _g3 = ref 0 in let _g4 = !missingCount in while !_g3 < _g4 do ignore \(\(',
        current_module_name_expr + 'ignore (if receiverPreApplied && HxArray.length (!fullArgs) = 2 && (HxString.equals c "deq (this_)" || HxString.equals c "eq (this_)") then (ignore (HxArray.push (!fullArgs) (HxExpr.ENull)); missingCount := 0) else ()); let firstSpacePreapplied = HxString.indexOf c " " 0 in let renderedCalleeHead = (if firstSpacePreapplied > 0 then HxString.substr c 0 firstSpacePreapplied else c : string) in let instanceQualifiedName = (if instanceCallName != Obj.magic (HxRuntime.hx_null) && String.length currentModuleNameForArity > 0 then ((currentModuleNameForArity) ^ "." ^ (instanceCallName : string) : string) else ("" : string) : string) in let renderedQualifiedName = (if String.length currentModuleNameForArity > 0 then ((currentModuleNameForArity) ^ "." ^ renderedCalleeHead : string) else ("" : string) : string) in let instanceSigResolved = (if instanceCallName != Obj.magic (HxRuntime.hx_null) then let rawInstanceSig = mapGetRaw (Obj.repr callSigByCallee) (instanceCallName : string) in if rawInstanceSig != Obj.magic (HxRuntime.hx_null) then Obj.magic rawInstanceSig else if String.length instanceQualifiedName > 0 then Obj.magic (mapGetRaw (Obj.repr callSigByCallee) (instanceQualifiedName : string)) else Obj.magic (HxRuntime.hx_null) else Obj.magic (HxRuntime.hx_null) : Obj.t) in let renderedSigResolved = (let rawRenderedSig = mapGetRaw (Obj.repr callSigByCallee) (renderedCalleeHead : string) in if rawRenderedSig != Obj.magic (HxRuntime.hx_null) then Obj.magic rawRenderedSig else if String.length renderedQualifiedName > 0 then Obj.magic (mapGetRaw (Obj.repr callSigByCallee) (renderedQualifiedName : string)) else Obj.magic (HxRuntime.hx_null) : Obj.t) in let instanceArityResolved = (if instanceCallName != Obj.magic (HxRuntime.hx_null) && mapHasRaw (Obj.repr arityByIdent) (instanceCallName : string) then Obj.obj (mapGetRaw (Obj.repr arityByIdent) (instanceCallName : string)) else if instanceCallName != Obj.magic (HxRuntime.hx_null) && String.length instanceQualifiedName > 0 && mapHasRaw (Obj.repr arityByIdent) (instanceQualifiedName : string) then Obj.obj (mapGetRaw (Obj.repr arityByIdent) (instanceQualifiedName : string)) else 0 : int) in let renderedArityResolved = (if mapHasRaw (Obj.repr arityByIdent) (renderedCalleeHead : string) then Obj.obj (mapGetRaw (Obj.repr arityByIdent) (renderedCalleeHead : string)) else if String.length renderedQualifiedName > 0 && mapHasRaw (Obj.repr arityByIdent) (renderedQualifiedName : string) then Obj.obj (mapGetRaw (Obj.repr arityByIdent) (renderedQualifiedName : string)) else 0 : int) in ignore (if receiverPreApplied && (Obj.magic (!hx_sig) != Obj.magic (HxRuntime.hx_null) || instanceSigResolved != Obj.magic (HxRuntime.hx_null) || renderedSigResolved != Obj.magic (HxRuntime.hx_null) || instanceArityResolved > 0 || renderedArityResolved > 0) then ignore (let expectedBySig = if Obj.magic (!hx_sig) != Obj.magic (HxRuntime.hx_null) then HxInt.sub (Obj.obj (HxAnon.get (Obj.magic (!hx_sig)) "expected")) preAppliedArgCount else 0 in let expectedByRecoveredInstanceSig = if instanceSigResolved != Obj.magic (HxRuntime.hx_null) then HxInt.sub (Obj.obj (HxAnon.get (Obj.magic instanceSigResolved) "expected")) preAppliedArgCount else 0 in let expectedByRecoveredRenderedSig = if renderedSigResolved != Obj.magic (HxRuntime.hx_null) then HxInt.sub (Obj.obj (HxAnon.get (Obj.magic renderedSigResolved) "expected")) preAppliedArgCount else 0 in let expectedByArity = if instanceArityResolved > 0 then HxInt.sub instanceArityResolved preAppliedArgCount else 0 in let expectedByRenderedCallee = if renderedArityResolved > 0 then HxInt.sub renderedArityResolved preAppliedArgCount else 0 in let bestRecovered = if expectedByRecoveredInstanceSig > expectedByRecoveredRenderedSig then expectedByRecoveredInstanceSig else expectedByRecoveredRenderedSig in let bestArity = if expectedByArity > expectedByRenderedCallee then expectedByArity else expectedByRenderedCallee in let bestSig = if expectedBySig > bestRecovered then expectedBySig else bestRecovered in let expectedAfterPreapply = if bestSig > bestArity then bestSig else bestArity in while HxArray.length (!fullArgs) < expectedAfterPreapply do ignore (HxArray.push (!fullArgs) (HxExpr.ENull)) done; let __assign_preapplied_final = 0 in (missingCount := __assign_preapplied_final;__assign_preapplied_final)) else ()); ignore (let _g3 = ref 0 in let _g4 = !missingCount in while !_g3 < _g4 do ignore ((',
        src,
    )
    patched_any = patched_any or final_preapplied_padding_count > 0

    if not patched_any:
        fail("build-hxhx: failed to locate bootstrap preapplied receiver arity branch\n")

    write_text(path_str, src + "\n(* hxhx(stage3) bootstrap shim: preapplied receiver arity repair *)\n")


def cmd_patch_string_length_fallback(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-string-length-fallback <path>\n")
    # Current source intentionally lowers these paths to `HxBootArray.length`.
    # The older bootstrap rewrite to `length_dyn` is no longer valid because the
    # runtime surface does not expose that symbol.
    return


def cmd_patch_string_length_stdlib(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-string-length-stdlib <path>\n")
    path_str = argv[0]
    src = read_text(path_str)
    old = '("String.length (" ^ HxString.toStdString o) ^ ")"'
    new = '("Stdlib.String.length (" ^ HxString.toStdString o) ^ ")"'
    count = src.count(old)
    if count == 0:
        return
    src = src.replace(old, new)
    write_text(path_str, src + "\n(* hxhx(stage3) bootstrap shim: string length stdlib repair *)\n")


def cmd_patch_mutable_local_string_init_hints(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-mutable-local-string-init-hints <path>\n")
    path_str = argv[0]
    src = read_text(path_str)
    old = '''                  | HxExpr.ECall (_p0, _p1) -> let _g = Obj.magic _p0 in let _g1 = Obj.magic _p1 in if (match _g with
                    | HxExpr.ENull -> 0
                    | HxExpr.EBool _ -> 1
                    | HxExpr.EString _ -> 2
                    | HxExpr.EInt _ -> 3
                    | HxExpr.EFloat _ -> 4
                    | HxExpr.EEnumValue _ -> 5
                    | HxExpr.EThis -> 6
                    | HxExpr.ESuper -> 7
                    | HxExpr.EIdent _ -> 8
                    | HxExpr.EField (_, _) -> 9
                    | HxExpr.ECall (_, _) -> 10
                    | HxExpr.ELambda (_, _) -> 11
                    | HxExpr.ETryCatchRaw _ -> 12
                    | HxExpr.ESwitchRaw _ -> 13
                    | HxExpr.ESwitch (_, _, _) -> 14
                    | HxExpr.ENew (_, _) -> 15
                    | HxExpr.EUnop (_, _) -> 16
                    | HxExpr.EBinop (_, _, _) -> 17
                    | HxExpr.ETernary (_, _, _) -> 18
                    | HxExpr.EAnon (_, _) -> 19
                    | HxExpr.EArrayComprehension (_, _, _) -> 20
                    | HxExpr.EArrayDecl _ -> 21
                    | HxExpr.EArrayAccess (_, _) -> 22
                    | HxExpr.ERange (_, _) -> 23
                    | HxExpr.ECast (_, _) -> 24
                    | HxExpr.EUntyped _ -> 25
                    | HxExpr.EUnsupported _ -> 26) = 8 then let _g2 = (match _g with
                    | HxExpr.EIdent __enum_param_45965 -> __enum_param_45965
                    | _ -> failwith "Unexpected enum parameter" : string) in let fn = (_g2 : string) in (
                    ignore _g1;
                    if mapGetRaw (Obj.repr fnReturnTypes) (fn : string) != Obj.magic (HxRuntime.hx_null) then let __assign_45966 = Obj.magic (mapGetRaw (Obj.repr fnReturnTypes) (fn : string)) in (
                      tempResult := __assign_45966;
                      __assign_45966
                    ) else let __assign_45967 = Obj.magic (TyType.unknown ()) in (
                      tempResult := __assign_45967;
                      __assign_45967
                    )
                  ) else let __assign_45968 = Obj.magic (TyType.unknown ()) in (
                    tempResult := __assign_45968;
                    __assign_45968
                  )'''
    new = '''                  | HxExpr.ECall (_p0, _p1) -> let _g = Obj.magic _p0 in let _g1 = Obj.magic _p1 in (
                    ignore _g1;
                    match _g with
                    | HxExpr.EIdent __enum_param_45965 -> let fn = (__enum_param_45965 : string) in if mapGetRaw (Obj.repr fnReturnTypes) (fn : string) != Obj.magic (HxRuntime.hx_null) then let __assign_45966 = Obj.magic (mapGetRaw (Obj.repr fnReturnTypes) (fn : string)) in (
                        tempResult := __assign_45966;
                        __assign_45966
                      ) else let __assign_45967 = Obj.magic (TyType.unknown ()) in (
                        tempResult := __assign_45967;
                        __assign_45967
                      )
                    | HxExpr.EField (_q0, _q1) -> let _g2 = Obj.magic _q0 in let field = (_q1 : string) in if HxString.equals field "string" && (match _g2 with
                      | HxExpr.EIdent __enum_param_std -> HxString.equals __enum_param_std "Std"
                      | _ -> false) then let __assign_45968 = Obj.magic (TyType.fromHintText ("String" : string)) in (
                        tempResult := __assign_45968;
                        __assign_45968
                      ) else if HxString.equals field "hex" && (match _g2 with
                      | HxExpr.EIdent __enum_param_hex -> HxString.equals __enum_param_hex "StringTools"
                      | _ -> false) then let __assign_45969 = Obj.magic (TyType.fromHintText ("String" : string)) in (
                        tempResult := __assign_45969;
                        __assign_45969
                      ) else if HxString.equals field "substr" || HxString.equals field "substring" || HxString.equals field "toLowerCase" || HxString.equals field "toUpperCase" || HxString.equals field "trim" || HxString.equals field "charAt" then let __assign_45970 = Obj.magic (TyType.fromHintText ("String" : string)) in (
                        tempResult := __assign_45970;
                        __assign_45970
                      ) else if HxString.equals field "stringify" || HxString.equals field "print" then let parts = tryExtractTypePathPartsFromExpr (Obj.magic _g2) in if parts != Obj.magic (HxRuntime.hx_null) && HxArray.length parts > 0 then let last = (HxArray.get (Obj.magic parts) (HxInt.sub (HxArray.length parts) 1) : string) in if (HxString.equals field "stringify" && (HxString.equals last "Json" || HxString.equals last "Haxe_Json")) || (HxString.equals field "print" && (HxString.equals last "JsonPrinter" || HxString.equals last "Haxe_format_JsonPrinter")) then let __assign_45971 = Obj.magic (TyType.fromHintText ("String" : string)) in (
                        tempResult := __assign_45971;
                        __assign_45971
                      ) else let __assign_45972 = Obj.magic (TyType.unknown ()) in (
                        tempResult := __assign_45972;
                        __assign_45972
                      ) else let __assign_45973 = Obj.magic (TyType.unknown ()) in (
                      tempResult := __assign_45973;
                      __assign_45973
                    ) else let __assign_45974 = Obj.magic (TyType.unknown ()) in (
                      tempResult := __assign_45974;
                      __assign_45974
                    )
                    | _ -> let __assign_45975 = Obj.magic (TyType.unknown ()) in (
                        tempResult := __assign_45975;
                        __assign_45975
                      )
                  )'''
    count = src.count(old)
    if count == 0:
        return
    src = src.replace(old, new)
    write_text(path_str, src + "\n(* hxhx(stage3) bootstrap shim: mutable-local string init hint repair *)\n")


def cmd_patch_qualified_static_optional_args(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-qualified-static-optional-args <path>\n")
    path_str = argv[0]
    src = read_text(path_str)
    pattern = re.compile(
        r'(?P<block>ignore \(if Obj\.magic \(!hx_sig\) == Obj\.magic \(HxRuntime\.hx_null\) '
        r'&& HxArray\.length args = 1 && \(HxString\.equals c "Php_Global\.class_exists" '
        r'\|\| HxString\.equals c "Php_Global\.interface_exists"\) then ignore \(\(\n'
        r'(?:(?:.|\n)*?)'
        r'\)\) else \(\)\);)'
    )
    replacement = (
        "\\g<block>\n"
        '                                                                  ignore (if Obj.magic (!hx_sig) == Obj.magic (HxRuntime.hx_null) && HxArray.length args = 1 && ((HxString.equals c "Json.stringify" || HxString.equals c "Haxe_Json.stringify") || (HxString.equals c "JsonPrinter.print" || HxString.equals c "Haxe_format_JsonPrinter.print")) then ignore ((\n'
        '                                                                    ignore (let __assign_json_optional = Obj.magic (let __arr_json_optional = HxArray.create () in (\n'
        '                                                                      ignore (HxArray.push __arr_json_optional (HxArray.get (Obj.magic args) 0));\n'
        '                                                                      ignore (HxArray.push __arr_json_optional (HxExpr.ENull));\n'
        '                                                                      ignore (HxArray.push __arr_json_optional (HxExpr.ENull));\n'
        '                                                                      __arr_json_optional\n'
        '                                                                    )) in (\n'
        '                                                                      fullArgs := __assign_json_optional;\n'
        '                                                                      __assign_json_optional\n'
        '                                                                    ));\n'
        '                                                                    let __assign_json_optional_missing = 0 in (\n'
        '                                                                      missingCount := __assign_json_optional_missing;\n'
        '                                                                      __assign_json_optional_missing\n'
        '                                                                    )\n'
        '                                                                  )) else ());\n'
        '                                                                  ignore (if Obj.magic (!hx_sig) == Obj.magic (HxRuntime.hx_null) && HxArray.length args = 1 && (HxString.equals c "Bytes.ofString" || HxString.equals c "Haxe_io_Bytes.ofString") then ignore ((\n'
        '                                                                    ignore (let __assign_bytes_optional = Obj.magic (let __arr_bytes_optional = HxArray.create () in (\n'
        '                                                                      ignore (HxArray.push __arr_bytes_optional (HxArray.get (Obj.magic args) 0));\n'
        '                                                                      ignore (HxArray.push __arr_bytes_optional (HxExpr.ENull));\n'
        '                                                                      __arr_bytes_optional\n'
        '                                                                    )) in (\n'
        '                                                                      fullArgs := __assign_bytes_optional;\n'
        '                                                                      __assign_bytes_optional\n'
        '                                                                    ));\n'
        '                                                                    let __assign_bytes_optional_missing = 0 in (\n'
        '                                                                      missingCount := __assign_bytes_optional_missing;\n'
        '                                                                      __assign_bytes_optional_missing\n'
        '                                                                    )\n'
        '                                                                  )) else ());\n'
        '                                                                  ignore (if Obj.magic (!hx_sig) == Obj.magic (HxRuntime.hx_null) && ((HxString.equals c "Assert.isTrue" || HxString.equals c "Utest_Assert.isTrue") || (HxString.equals c "Assert.isFalse" || HxString.equals c "Utest_Assert.isFalse")) && HxArray.length args = 2 then ignore ((\n'
        '                                                                    ignore (let __assign_assert_bool = Obj.magic (let __arr_assert_bool = HxArray.create () in (\n'
        '                                                                      ignore (HxArray.push __arr_assert_bool (HxArray.get (Obj.magic args) 0));\n'
        '                                                                      ignore (HxArray.push __arr_assert_bool (HxExpr.ENull));\n'
        '                                                                      ignore (HxArray.push __arr_assert_bool (HxArray.get (Obj.magic args) 1));\n'
        '                                                                      __arr_assert_bool\n'
        '                                                                    )) in (\n'
        '                                                                      fullArgs := __assign_assert_bool;\n'
        '                                                                      __assign_assert_bool\n'
        '                                                                    ));\n'
        '                                                                    let __assign_assert_bool_missing = 0 in (\n'
        '                                                                      missingCount := __assign_assert_bool_missing;\n'
        '                                                                      __assign_assert_bool_missing\n'
        '                                                                    )\n'
        '                                                                  )) else ());\n'
        '                                                                  ignore (if Obj.magic (!hx_sig) == Obj.magic (HxRuntime.hx_null) && ((HxString.equals c "Assert.equals" || HxString.equals c "Utest_Assert.equals") || (HxString.equals c "Assert.contains" || HxString.equals c "Utest_Assert.contains")) && HxArray.length args = 3 then ignore ((\n'
        '                                                                    ignore (let __assign_assert_eq = Obj.magic (let __arr_assert_eq = HxArray.create () in (\n'
        '                                                                      ignore (HxArray.push __arr_assert_eq (HxArray.get (Obj.magic args) 0));\n'
        '                                                                      ignore (HxArray.push __arr_assert_eq (HxArray.get (Obj.magic args) 1));\n'
        '                                                                      ignore (HxArray.push __arr_assert_eq (HxExpr.ENull));\n'
        '                                                                      ignore (HxArray.push __arr_assert_eq (HxArray.get (Obj.magic args) 2));\n'
        '                                                                      __arr_assert_eq\n'
        '                                                                    )) in (\n'
        '                                                                      fullArgs := __assign_assert_eq;\n'
        '                                                                      __assign_assert_eq\n'
        '                                                                    ));\n'
        '                                                                    let __assign_assert_eq_missing = 0 in (\n'
        '                                                                      missingCount := __assign_assert_eq_missing;\n'
        '                                                                      __assign_assert_eq_missing\n'
        '                                                                    )\n'
        '                                                                  )) else ());\n'
        '                                                                  ignore (if Obj.magic (!hx_sig) == Obj.magic (HxRuntime.hx_null) && (HxString.equals c "Assert.floatEquals" || HxString.equals c "Utest_Assert.floatEquals") && HxArray.length args = 3 then ignore ((\n'
        '                                                                    ignore (let __assign_assert_float = Obj.magic (let __arr_assert_float = HxArray.create () in (\n'
        '                                                                      ignore (HxArray.push __arr_assert_float (HxArray.get (Obj.magic args) 0));\n'
        '                                                                      ignore (HxArray.push __arr_assert_float (HxArray.get (Obj.magic args) 1));\n'
        '                                                                      ignore (HxArray.push __arr_assert_float (HxExpr.ENull));\n'
        '                                                                      ignore (HxArray.push __arr_assert_float (HxExpr.ENull));\n'
        '                                                                      ignore (HxArray.push __arr_assert_float (HxArray.get (Obj.magic args) 2));\n'
        '                                                                      __arr_assert_float\n'
        '                                                                    )) in (\n'
        '                                                                      fullArgs := __assign_assert_float;\n'
        '                                                                      __assign_assert_float\n'
        '                                                                    ));\n'
        '                                                                    let __assign_assert_float_missing = 0 in (\n'
        '                                                                      missingCount := __assign_assert_float_missing;\n'
        '                                                                      __assign_assert_float_missing\n'
        '                                                                    )\n'
        '                                                                  )) else ());\n'
        '                                                                  ignore (if Obj.magic (!hx_sig) == Obj.magic (HxRuntime.hx_null) && (HxString.equals c "Assert.same" || HxString.equals c "Utest_Assert.same") && HxArray.length args = 3 then ignore ((\n'
        '                                                                    ignore (let __assign_assert_same = Obj.magic (let __arr_assert_same = HxArray.create () in (\n'
        '                                                                      ignore (HxArray.push __arr_assert_same (HxArray.get (Obj.magic args) 0));\n'
        '                                                                      ignore (HxArray.push __arr_assert_same (HxArray.get (Obj.magic args) 1));\n'
        '                                                                      ignore (HxArray.push __arr_assert_same (HxExpr.ENull));\n'
        '                                                                      ignore (HxArray.push __arr_assert_same (HxExpr.ENull));\n'
        '                                                                      ignore (HxArray.push __arr_assert_same (HxExpr.ENull));\n'
        '                                                                      ignore (HxArray.push __arr_assert_same (HxArray.get (Obj.magic args) 2));\n'
        '                                                                      __arr_assert_same\n'
        '                                                                    )) in (\n'
        '                                                                      fullArgs := __assign_assert_same;\n'
        '                                                                      __assign_assert_same\n'
        '                                                                    ));\n'
        '                                                                    let __assign_assert_same_missing = 0 in (\n'
        '                                                                      missingCount := __assign_assert_same_missing;\n'
        '                                                                      __assign_assert_same_missing\n'
        '                                                                    )\n'
        '                                                                  )) else ());\n'
        '                                                                  ignore (if Obj.magic (!hx_sig) == Obj.magic (HxRuntime.hx_null) && (HxString.equals c "Assert.raises" || HxString.equals c "Utest_Assert.raises") && HxArray.length args = 2 then ignore ((\n'
        '                                                                    ignore (let __assign_assert_raises = Obj.magic (let __arr_assert_raises = HxArray.create () in (\n'
        '                                                                      ignore (HxArray.push __arr_assert_raises (HxArray.get (Obj.magic args) 0));\n'
        '                                                                      ignore (HxArray.push __arr_assert_raises (HxExpr.ENull));\n'
        '                                                                      ignore (HxArray.push __arr_assert_raises (HxExpr.ENull));\n'
        '                                                                      ignore (HxArray.push __arr_assert_raises (HxExpr.ENull));\n'
        '                                                                      ignore (HxArray.push __arr_assert_raises (HxArray.get (Obj.magic args) 1));\n'
        '                                                                      __arr_assert_raises\n'
        '                                                                    )) in (\n'
        '                                                                      fullArgs := __assign_assert_raises;\n'
        '                                                                      __assign_assert_raises\n'
        '                                                                    ));\n'
        '                                                                    let __assign_assert_raises_missing = 0 in (\n'
        '                                                                      missingCount := __assign_assert_raises_missing;\n'
        '                                                                      __assign_assert_raises_missing\n'
        '                                                                    )\n'
        '                                                                  )) else ());'
    )
    src, count = pattern.subn(replacement, src)
    if count == 0:
        return
    write_text(path_str, src + "\n(* hxhx(stage3) bootstrap shim: qualified static optional-arg padding repair *)\n")


def cmd_patch_preapplied_getstring_optional_arg(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-preapplied-getstring-optional-arg <path>\n")
    path_str = argv[0]
    src = read_text(path_str)
    if 'HxString.equals c "getString"' not in src and 'HxString.equals c "getString (this_)"' not in src and "!fullArgs" not in src:
        return
    if 'HxString.equals c "getString (this_)"' in src:
        write_text(path_str, src)
        return
    pattern = re.compile(
        r'ignore \(if HxString\.equals c "getString" && '
        r'\(mapGetRaw \(Obj\.repr tyByIdent\) \(!(?P<temp_a>tempString\d+) : string\) != Obj\.magic \(HxRuntime\.hx_null\) '
        r'\|\| mapGetRaw \(Obj\.repr tyByIdent\) \(!(?P<temp_b>tempString\d+) : string\) != Obj\.magic \(HxRuntime\.hx_null\)\) '
        r'&& HxArray\.length \(!fullArgs\) = 2 then ignore \(\(\n'
        r'\s*ignore \(let __assign_\d+ = Obj\.magic \(let __arr_\d+ = HxArray\.create \(\) in \(\n'
        r'\s*ignore \(HxArray\.push __arr_\d+ \(HxExpr\.EThis\)\);\n'
        r'\s*ignore \(HxArray\.push __arr_\d+ \(HxArray\.get \(Obj\.magic \(!fullArgs\)\) 0\)\);\n'
        r'\s*ignore \(HxArray\.push __arr_\d+ \(HxArray\.get \(Obj\.magic \(!fullArgs\)\) 1\)\);\n'
        r'\s*ignore \(HxArray\.push __arr_\d+ \(HxExpr\.ENull\)\);\n'
        r'\s*__arr_\d+\n'
        r'\s*\)\) in \(\n'
        r'\s*fullArgs := __assign_\d+;\n'
        r'\s*__assign_\d+\n'
        r'\s*\)\);\n'
        r'\s*let __assign_\d+ = 0 in \(\n'
        r'\s*missingCount := __assign_\d+;\n'
        r'\s*__assign_\d+\n'
        r'\s*\)\n'
        r'\s*\)\) else \(\)\);'
    )
    def replacement(match: re.Match[str]) -> str:
        temp_a = match.group("temp_a")
        temp_b = match.group("temp_b")
        return f'''ignore (if (((HxString.equals c "getString" && (mapGetRaw (Obj.repr tyByIdent) (!{temp_a} : string) != Obj.magic (HxRuntime.hx_null) || mapGetRaw (Obj.repr tyByIdent) (!{temp_b} : string) != Obj.magic (HxRuntime.hx_null))) || HxString.equals c "getString (this_)")) && HxArray.length (!fullArgs) = 2 then ignore ((
                                                                        ignore (let __assign_getstring = Obj.magic (let __arr_getstring = HxArray.create () in (
                                                                          ignore (if HxString.equals c "getString" then ignore (HxArray.push __arr_getstring (HxExpr.EThis)) else ignore ());
                                                                          ignore (HxArray.push __arr_getstring (HxArray.get (Obj.magic (!fullArgs)) 0));
                                                                          ignore (HxArray.push __arr_getstring (HxArray.get (Obj.magic (!fullArgs)) 1));
                                                                          ignore (HxArray.push __arr_getstring (HxExpr.ENull));
                                                                          __arr_getstring
                                                                        )) in (
                                                                          fullArgs := __assign_getstring;
                                                                          __assign_getstring
                                                                        ));
                                                                        let __assign_getstring_missing = 0 in (
                                                                          missingCount := __assign_getstring_missing;
                                                                          __assign_getstring_missing
                                                                        )
                                                                      )) else ());'''
    src, count = pattern.subn(replacement, src)
    if count == 0:
        current_pattern = re.compile(
            r'ignore \(if HxString\.equals c "getString" && '
            r'\(typedMapGet tyByIdent \(!(?P<temp_a>tempString\d+) : string\) != Obj\.magic \(HxRuntime\.hx_null\) '
            r'\|\| typedMapGet tyByIdent \(!(?P<temp_b>tempString\d+) : string\) != Obj\.magic \(HxRuntime\.hx_null\)\) '
            r'&& HxArray\.length \(!fullArgs\) = 2 then ignore \(\(\n'
            r'\s*ignore \(let __assign_\d+ = Obj\.magic \(let __arr_\d+ = HxArray\.create \(\) in \(\n'
            r'\s*ignore \(HxArray\.push __arr_\d+ \(HxExpr\.EThis\)\);\n'
            r'\s*ignore \(HxArray\.push __arr_\d+ \(HxArray\.get \(Obj\.magic \(!fullArgs\)\) 0\)\);\n'
            r'\s*ignore \(HxArray\.push __arr_\d+ \(HxArray\.get \(Obj\.magic \(!fullArgs\)\) 1\)\);\n'
            r'\s*ignore \(HxArray\.push __arr_\d+ \(HxExpr\.ENull\)\);\n'
            r'\s*__arr_\d+\n'
            r'\s*\)\) in \(\n'
            r'\s*fullArgs := __assign_\d+;\n'
            r'\s*__assign_\d+\n'
            r'\s*\)\);\n'
            r'\s*let __assign_\d+ = 0 in \(\n'
            r'\s*missingCount := __assign_\d+;\n'
            r'\s*__assign_\d+\n'
            r'\s*\)\n'
            r'\s*\)\) else \(\)\);'
        )

        def current_replacement(match: re.Match[str]) -> str:
            temp_a = match.group("temp_a")
            temp_b = match.group("temp_b")
            return f'''ignore (if (((HxString.equals c "getString" && (typedMapGet tyByIdent (!{temp_a} : string) != Obj.magic (HxRuntime.hx_null) || typedMapGet tyByIdent (!{temp_b} : string) != Obj.magic (HxRuntime.hx_null))) || HxString.equals c "getString (this_)")) && HxArray.length (!fullArgs) = 2 then ignore ((
                                                                        ignore (let __assign_getstring = Obj.magic (let __arr_getstring = HxArray.create () in (
                                                                          ignore (if HxString.equals c "getString" then ignore (HxArray.push __arr_getstring (HxExpr.EThis)) else ignore ());
                                                                          ignore (HxArray.push __arr_getstring (HxArray.get (Obj.magic (!fullArgs)) 0));
                                                                          ignore (HxArray.push __arr_getstring (HxArray.get (Obj.magic (!fullArgs)) 1));
                                                                          ignore (HxArray.push __arr_getstring (HxExpr.ENull));
                                                                          __arr_getstring
                                                                        )) in (
                                                                          fullArgs := __assign_getstring;
                                                                          __assign_getstring
                                                                        ));
                                                                        let __assign_getstring_missing = 0 in (
                                                                          missingCount := __assign_getstring_missing;
                                                                          __assign_getstring_missing
                                                                        )
                                                                      )) else ());'''

        src, count = current_pattern.subn(current_replacement, src)
    if count == 0:
        write_text(path_str, src)
        return
    write_text(path_str, src + "\n(* hxhx(stage3) bootstrap shim: preapplied getString optional-arg repair *)\n")


def cmd_patch_lambda_list_shim(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-lambda-list-shim <path>\n")
    path_str = argv[0]
    src = read_text(path_str)
    pattern = re.compile(
        re.escape('("(* hxhx(stage3) bootstrap shim: Lambda *)\\n" ^ "let array it =\\n" ^ "  HxBootArray.of_list (List.of_seq (it : _ Seq.t))\\n" ^ ')
        + r'.*?'
        + re.escape('"let count _ = 0\\n")'),
        re.DOTALL,
    )
    replacement = '''("(* hxhx(stage3) bootstrap shim: Lambda *)\n" ^ "type __hx_iterable = { iterator : Obj.t -> unit -> Obj.t HxIterator.t }\n" ^ "let __hx_iter_any it f =\n" ^ "  let __hx_make_iterator_raw = HxAnon.get (Obj.repr (Obj.magic it)) \\"iterator\\" in\n" ^ "  let __hx_iterator =\n" ^ "    if __hx_make_iterator_raw != HxRuntime.hx_null then\n" ^ "      let __hx_make_iterator = (Obj.obj __hx_make_iterator_raw : unit -> Obj.t) in\n" ^ "      (Obj.magic (__hx_make_iterator ()) : _ HxIterator.t)\n" ^ "    else\n" ^ "      let __hx_make_iterator = ((Obj.magic it : __hx_iterable).iterator) in\n" ^ "      __hx_make_iterator (Obj.magic it) ()\n" ^ "  in\n" ^ "  while HxIterator.hasNext (__hx_iterator) do\n" ^ "    f (HxIterator.next (__hx_iterator))\n" ^ "  done\n" ^ "let array it =\n" ^ "  let __hx_acc = ref [] in\n" ^ "  __hx_iter_any it (fun x -> __hx_acc := x :: !__hx_acc);\n" ^ "  HxBootArray.of_list (List.rev (!__hx_acc))\n" ^ "let list it =\n" ^ "  let __hx_obj = Haxe_ds_List.create () in\n" ^ "  __hx_iter_any it (fun x -> ignore (Haxe_ds_List.add (__hx_obj) x));\n" ^ "  __hx_obj\n" ^ "let fold it f first =\n" ^ "  let acc = ref first in\n" ^ "  __hx_iter_any it (fun x -> acc := f x !acc);\n" ^ "  !acc\n" ^ "let has it v =\n" ^ "  let found = ref false in\n" ^ "  let __hx_value = Obj.repr v in\n" ^ "  __hx_iter_any it (fun x -> if not (!found) && x = __hx_value then found := true);\n" ^ "  !found\n" ^ "let exists it f =\n" ^ "  let found = ref false in\n" ^ "  __hx_iter_any it (fun x -> if not (!found) && f x then found := true);\n" ^ "  !found\n" ^ "let iter it f =\n" ^ "  __hx_iter_any it f\n" ^ "let count it =\n" ^ "  let n = ref 0 in\n" ^ "  __hx_iter_any it (fun _ -> n := !n + 1);\n" ^ "  !n\n")'''
    src, count = pattern.subn(replacement, src, count=1)
    if count == 0:
        return
    write_text(path_str, src + "\n(* hxhx(stage3) bootstrap shim: Lambda iterable repair *)\n")


def cmd_patch_haxe_ds_list_shim(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-haxe-ds-list-shim <path>\n")
    path_str = argv[0]
    src = read_text(path_str)
    marker = '(* hxhx(stage3) bootstrap shim: haxe.ds.List *)'
    if marker in src:
        write_text(path_str, src)
        return

    anchor = '        ignore (let shimName = ("HxBootArray" : string) in let shimPath = (Haxe_io_Path.join'
    content = """(* hxhx(stage3) bootstrap shim: haxe.ds.List *)
type t = {
  mutable __hx_type : Obj.t;
  mutable values : Obj.t HxArray.t;
  mutable length : int;
  add : Obj.t -> Obj.t -> unit;
  push : Obj.t -> Obj.t -> unit;
  first : Obj.t -> unit -> Obj.t;
  last : Obj.t -> unit -> Obj.t;
  pop : Obj.t -> unit -> Obj.t;
  isEmpty : Obj.t -> unit -> bool;
  clear : Obj.t -> unit -> unit;
  remove : Obj.t -> Obj.t -> bool;
  iterator : Obj.t -> unit -> Obj.t HxIterator.t;
  join : Obj.t -> string -> string;
  toString : Obj.t -> unit -> string;
}
let add__impl = fun (self : t) item ->
  ignore (HxArray.push ((Obj.magic self : t).values) item);
  (Obj.magic self : t).length <- HxArray.length ((Obj.magic self : t).values)
let push__impl = fun (self : t) item ->
  let next = HxArray.create () in
  let prev = ((Obj.magic self : t).values : Obj.t HxArray.t) in
  ignore (HxArray.push next item);
  ignore (let _g = ref 0 in while !_g < HxArray.length prev do ignore (let value = HxArray.get (Obj.magic prev) (!_g) in (
    ignore (let __old = !_g in let __new = HxInt.add __old 1 in (
      ignore (_g := __new);
      __new
    ));
    ignore (HxArray.push next value)
  )) done);
  (Obj.magic self : t).values <- next;
  (Obj.magic self : t).length <- HxArray.length next
let first__impl = fun (self : t) () ->
  if (Obj.magic self : t).length = 0 then Obj.magic HxRuntime.hx_null else HxArray.get ((Obj.magic self : t).values) 0
let last__impl = fun (self : t) () ->
  if (Obj.magic self : t).length = 0 then Obj.magic HxRuntime.hx_null else HxArray.get ((Obj.magic self : t).values) (HxInt.sub ((Obj.magic self : t).length) 1)
let pop__impl = fun (self : t) () ->
  let value = HxArray.shift ((Obj.magic self : t).values) () in
  (Obj.magic self : t).length <- HxArray.length ((Obj.magic self : t).values);
  value
let isEmpty__impl = fun (self : t) () -> (Obj.magic self : t).length = 0
let clear__impl = fun (self : t) () ->
  (Obj.magic self : t).values <- HxArray.create ();
  (Obj.magic self : t).length <- 0
let remove__impl = fun (self : t) value ->
  let removed = HxArray.remove ((Obj.magic self : t).values) value in
  if removed then (Obj.magic self : t).length <- HxArray.length ((Obj.magic self : t).values) else ();
  removed
let iterator__impl = fun (self : t) () -> HxIterator.of_array ((Obj.magic self : t).values)
let join__impl = fun (self : t) sep -> HxArray.join ((Obj.magic self : t).values) sep Std.string
let toString__impl = fun (self : t) () -> (("{" : string) ^ HxString.toStdString (join__impl (Obj.magic self) (", " : string))) ^ ("}" : string)
let __empty = fun () -> ({ __hx_type = HxType.class_ "haxe.ds.List"; values = HxArray.create (); length = 0; add = (fun o a0 -> Obj.magic (add__impl (Obj.magic o) (Obj.magic a0))); push = (fun o a0 -> Obj.magic (push__impl (Obj.magic o) (Obj.magic a0))); first = (fun o () -> Obj.magic (first__impl (Obj.magic o) ())); last = (fun o () -> Obj.magic (last__impl (Obj.magic o) ())); pop = (fun o () -> Obj.magic (pop__impl (Obj.magic o) ())); isEmpty = (fun o () -> Obj.magic (isEmpty__impl (Obj.magic o) ())); clear = (fun o () -> Obj.magic (clear__impl (Obj.magic o) ())); remove = (fun o a0 -> Obj.magic (remove__impl (Obj.magic o) (Obj.magic a0))); iterator = (fun o () -> Obj.magic (iterator__impl (Obj.magic o) ())); join = (fun o a0 -> Obj.magic (join__impl (Obj.magic o) (Obj.magic a0))); toString = (fun o () -> Obj.magic (toString__impl (Obj.magic o) ())) } : t)
let new_ = fun (self : t) ->
  (Obj.magic self : t).__hx_type <- HxType.class_ "haxe.ds.List";
  (Obj.magic self : t).values <- HxArray.create ();
  (Obj.magic self : t).length <- 0;
  self
let create = fun () -> let self = (__empty () : t) in
  ignore (new_ (Obj.magic self));
  self
let add = fun (self : t) item -> add__impl (Obj.magic self) item
let push = fun (self : t) item -> push__impl (Obj.magic self) item
let first = fun (self : t) () -> first__impl (Obj.magic self) ()
let last = fun (self : t) () -> last__impl (Obj.magic self) ()
let pop = fun (self : t) () -> pop__impl (Obj.magic self) ()
let isEmpty = fun (self : t) () -> isEmpty__impl (Obj.magic self) ()
let clear = fun (self : t) () -> clear__impl (Obj.magic self) ()
let remove = fun (self : t) value -> remove__impl (Obj.magic self) value
let iterator = fun (self : t) () -> iterator__impl (Obj.magic self) ()
let join = fun (self : t) sep -> join__impl (Obj.magic self) sep
let toString = fun (self : t) () -> toString__impl (Obj.magic self) ()
"""
    escaped = content.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    insertion = f'''        ignore (let shimName = ("Haxe_ds_List" : string) in let shimPath = (Haxe_io_Path.join (Obj.magic (let __arr_lambda_list = HxArray.create () in (
          ignore (HxArray.push __arr_lambda_list outAbs);
          ignore (HxArray.push __arr_lambda_list (HxString.toStdString shimName ^ ".ml"));
          __arr_lambda_list
        ))) : string) in (
          ignore (if not (HxFileSystem.exists shimPath) then ignore (HxFile.saveContent (shimPath : string) ("{escaped}" : string)) else (let existing = (HxFile.getContent (shimPath : string) : string) in ignore (if (HxString.indexOf existing ("let create" : string) 0) < 0 && (HxString.indexOf existing ("let rec create" : string) 0) < 0 then ignore (HxFile.saveContent (shimPath : string) ("{escaped}" : string)) else ())));
          HxArray.push generatedPaths (HxString.toStdString shimName ^ ".ml")
        ));
'''
    if anchor not in src:
        return
    src = src.replace(anchor, insertion + anchor, 1)

    late_anchor = '                            let rootMainPath = (Obj.obj (HxAnon.get rr "rootMain") : string) in (\n' \
        '                              ignore (let shimName = ("StringTools" : string) in let shimFile = (HxString.toStdString shimName ^ ".ml" : string) in let shimPath = (Haxe_io_Path.join'
    late_insertion = f'''                            let rootMainPath = (Obj.obj (HxAnon.get rr "rootMain") : string) in (
                              ignore (let shimName = ("Haxe_ds_List" : string) in let shimFile = (HxString.toStdString shimName ^ ".ml" : string) in let shimPath = (Haxe_io_Path.join (Obj.magic (let __arr_hx_list_repair = HxArray.create () in (
                                ignore (HxArray.push __arr_hx_list_repair outAbs);
                                ignore (HxArray.push __arr_hx_list_repair shimFile);
                                __arr_hx_list_repair
                              ))) : string) in try if HxFileSystem.exists shimPath then ignore (let contents = (HxFile.getContent (shimPath : string) : string) in let hasCreate = HxString.indexOf contents ("let create" : string) 0 <> -1 || HxString.indexOf contents ("let rec create" : string) 0 <> -1 in if not (hasCreate) then ignore (HxFile.saveContent (shimPath : string) ("{escaped}" : string)) else ()) else ignore ((
                                ignore (HxFile.saveContent (shimPath : string) ("{escaped}" : string));
                                HxArray.push generatedPaths shimFile
                              )) with
                                | HxRuntime.Hx_break -> raise (HxRuntime.Hx_break)
                                | HxRuntime.Hx_continue -> raise (HxRuntime.Hx_continue)
                                | HxRuntime.Hx_return __ret_hx_list_repair -> raise (HxRuntime.Hx_return __ret_hx_list_repair)
                                | HxRuntime.Hx_exception (__exn_v_hx_list_repair, __exn_tags_hx_list_repair) -> if HxRuntime.tags_has __exn_tags_hx_list_repair "haxe.io.Error" then let _hx = (Obj.obj (HxEnum.unbox_or_obj "haxe.io.Error" __exn_v_hx_list_repair) : Haxe_io_Error.error) in (
                                  ignore _hx;
                                  ()
                                ) else if HxRuntime.tags_has __exn_tags_hx_list_repair "String" then let _hx = (Obj.obj __exn_v_hx_list_repair : string) in (
                                  ignore _hx;
                                  ()
                                ) else HxRuntime.hx_throw_typed __exn_v_hx_list_repair __exn_tags_hx_list_repair
                                | __exn_hx_list_repair -> if HxRuntime.tags_has ["OcamlExn"] "haxe.io.Error" then let _hx = (Obj.obj (HxEnum.unbox_or_obj "haxe.io.Error" (Obj.repr __exn_hx_list_repair)) : Haxe_io_Error.error) in (
                                  ignore _hx;
                                  ()
                                ) else if HxRuntime.tags_has ["OcamlExn"] "String" then let _hx = (Obj.obj (Obj.repr __exn_hx_list_repair) : string) in (
                                  ignore _hx;
                                  ()
                                ) else raise (__exn_hx_list_repair));
                              ignore (let shimName = ("StringTools" : string) in let shimFile = (HxString.toStdString shimName ^ ".ml" : string) in let shimPath = (Haxe_io_Path.join'''
    if late_anchor not in src:
        write_text(path_str, src)
        return
    src = src.replace(late_anchor, late_insertion, 1)
    write_text(path_str, src + "\n(* hxhx(stage3) bootstrap shim: haxe.ds.List repair *)\n")


def cmd_patch_string_key_cast_index(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-string-key-cast-index <path>\n")
    path_str = argv[0]
    src = read_text(path_str)
    old = '''              | HxExpr.EIdent _p0 -> let _g = (_p0 : string) in let name = (_g : string) in let __assign_278 = HxString.equals (tyForIdent (name : string)) "String" in (
                tempResult6 := __assign_278;
                __assign_278
              )
              | HxExpr.ECall (_p0, _p1) -> let _g = Obj.magic _p0 in let _g1 = Obj.magic _p1 in if (match _g with'''
    new = '''              | HxExpr.EIdent _p0 -> let _g = (_p0 : string) in let name = (_g : string) in let __assign_278 = HxString.equals (tyForIdent (name : string)) "String" in (
                tempResult6 := __assign_278;
                __assign_278
              )
              | HxExpr.ECast (_p0, _p1) -> let _g = Obj.magic _p0 in let _g1 = (_p1 : string) in (
                ignore _g1;
                let inner = Obj.magic _g in let __assign_279 = (!isStringExpr) (Obj.magic inner) in (
                  tempResult6 := __assign_279;
                  __assign_279
                )
              )
              | HxExpr.EUntyped _p0 -> let _g = Obj.magic _p0 in let inner = Obj.magic _g in let __assign_280 = (!isStringExpr) (Obj.magic inner) in (
                tempResult6 := __assign_280;
                __assign_280
              )
              | HxExpr.ECall (_p0, _p1) -> let _g = Obj.magic _p0 in let _g1 = Obj.magic _p1 in if (match _g with'''
    if old not in src:
        return
    src = src.replace(old, new, 1)
    old_array_guard = 'let arr = Obj.magic _g in let idx = Obj.magic _g1 in if (!isStringExpr) (Obj.magic idx) then ('
    new_array_guard = '''let arr = Obj.magic _g in let idx = Obj.magic _g1 in let isStringKeyIndex = if (!isStringExpr) (Obj.magic idx) then true else (match idx with
                          | HxExpr.ECast (_p2, _p3) -> let _g2 = Obj.magic _p2 in let _g3 = (_p3 : string) in (
                            ignore _g3;
                            let inner = Obj.magic _g2 in (match inner with
                              | HxExpr.EIdent _ -> true
                              | HxExpr.EField (_, _) -> true
                              | _ -> (!isStringExpr) (Obj.magic inner))
                          )
                          | HxExpr.EUntyped _p2 -> let _g2 = Obj.magic _p2 in (!isStringExpr) (Obj.magic _g2)
                          | _ -> false) in if isStringKeyIndex then ('''
    if old_array_guard not in src:
        return
    src = src.replace(old_array_guard, new_array_guard, 1)
    write_text(path_str, src + "\n(* hxhx(stage3) bootstrap shim: string-key cast index repair *)\n")


def cmd_patch_stringtools_hex_optional_digits(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-stringtools-hex-optional-digits <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    old_hex_case = '''                              | "hex" -> if HxArray.length _g1 = 1 then let _g5 = Obj.magic (HxArray.get (Obj.magic _g1) 0) in let n = Obj.magic _g5 in let __assign_25985 = (("StringTools.hex (" ^ HxString.toStdString (exprToOcaml (Obj.magic n) (Obj.repr arityByIdent) (Obj.repr tyByIdent) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee))) ^ ") (0)" : string) in (
                                tempResult13 := __assign_25985;
                                __assign_25985
                              ) else let callee = Obj.magic _g in let args = Obj.magic _g1 in ('''
    new_hex_case = '''                              | "hex" -> if HxArray.length _g1 = 1 then let _g5 = Obj.magic (HxArray.get (Obj.magic _g1) 0) in let n = Obj.magic _g5 in let __assign_25985 = (("StringTools.hex (" ^ HxString.toStdString (exprToOcaml (Obj.magic n) (Obj.repr arityByIdent) (Obj.repr tyByIdent) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee))) ^ ") (Obj.repr 0)" : string) in (
                                tempResult13 := __assign_25985;
                                __assign_25985
                              ) else if HxArray.length _g1 = 2 then let _g5 = Obj.magic (HxArray.get (Obj.magic _g1) 0) in let _g6 = Obj.magic (HxArray.get (Obj.magic _g1) 1) in let n = Obj.magic _g5 in let digits = Obj.magic _g6 in let __assign_25985 = (((("StringTools.hex (" ^ HxString.toStdString (exprToOcaml (Obj.magic n) (Obj.repr arityByIdent) (Obj.repr tyByIdent) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee))) ^ ") (") ^ HxString.toStdString (match digits with
                                | HxExpr.ENull -> ("(Obj.magic HxRuntime.hx_null)" : string)
                                | _ -> (("(Obj.repr (" ^ HxString.toStdString (exprToOcaml (Obj.magic digits) (Obj.repr arityByIdent) (Obj.repr tyByIdent) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee))) ^ "))" : string))) ^ ")" : string) in (
                                tempResult13 := __assign_25985;
                                __assign_25985
                              ) else let callee = Obj.magic _g in let args = Obj.magic _g1 in ('''

    if old_hex_case not in src:
        return
    src = src.replace(old_hex_case, new_hex_case, 1)
    write_text(path_str, src + "\n(* hxhx(stage3) bootstrap shim: StringTools.hex optional digits repair *)\n")


def cmd_patch_mutable_int64_assignment(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-mutable-int64-assignment <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    if "inferInitType" not in src and "Haxe_Int64.ofInt" not in src:
        return

    old_seed = '''                    let existing = Obj.magic (HxMap.get_string localHints name) in let inferred = Obj.magic ((!inferInitType) (Obj.obj (HxEnum.unbox_or_obj "HxExpr" init)) (Obj.magic (HxRuntime.hx_null)) (Obj.magic (HxRuntime.hx_null))) in let existingNeedsUpgrade = existing == Obj.magic (HxRuntime.hx_null) || TyType.isUnknown (Obj.magic existing) () || HxString.equals (TyType.toString (Obj.magic existing) ()) "Dynamic" || HxString.equals (TyType.toString (Obj.magic existing) ()) "Array" in let inferredUseful = not (TyType.isUnknown (Obj.magic inferred) ()) && not (HxString.equals (TyType.toString (Obj.magic inferred) ()) "Dynamic") in if existingNeedsUpgrade && inferredUseful then ignore (HxMap.set_string localHints name inferred) else ()'''
    new_seed = '''                    let existing = Obj.magic (HxMap.get_string localHints name) in let declared = if _g1 == Obj.magic (HxRuntime.hx_null) || HxString.length _g1 = 0 then Obj.magic (HxRuntime.hx_null) else Obj.magic (TyType.fromHintText (StringTools.trim (_g1 : string))) in let inferred = if declared != Obj.magic (HxRuntime.hx_null) then Obj.magic declared else Obj.magic ((!inferInitType) (Obj.obj (HxEnum.unbox_or_obj "HxExpr" init)) (Obj.magic (HxRuntime.hx_null)) (Obj.magic (HxRuntime.hx_null))) in let existingNeedsUpgrade = existing == Obj.magic (HxRuntime.hx_null) || TyType.isUnknown (Obj.magic existing) () || HxString.equals (TyType.toString (Obj.magic existing) ()) "Dynamic" || HxString.equals (TyType.toString (Obj.magic existing) ()) "Array" in let preferInferredInt64 = inferred != Obj.magic (HxRuntime.hx_null) && (HxString.equals (TyType.toString (Obj.magic inferred) ()) "Int64" || HxString.equals (TyType.toString (Obj.magic inferred) ()) "haxe.Int64") && (existing == Obj.magic (HxRuntime.hx_null) || (not (HxString.equals (TyType.toString (Obj.magic existing) ()) "Int64") && not (HxString.equals (TyType.toString (Obj.magic existing) ()) "haxe.Int64"))) in let inferredUseful = not (TyType.isUnknown (Obj.magic inferred) ()) && not (HxString.equals (TyType.toString (Obj.magic inferred) ()) "Dynamic") in if (existingNeedsUpgrade || preferInferredInt64) && inferredUseful then ignore (HxMap.set_string localHints name inferred) else ()'''

    old_assign = '''                      | "=" -> let __assign_46076 = Obj.magic (returnExprToOcaml (Obj.magic rhs) allowedValueIdentsForStmt (Obj.magic (Obj.magic (HxRuntime.hx_null))) (Obj.repr arityByIdent) (Obj.repr tyCtx) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee) : string) in (
                        tempMaybeString := __assign_46076;
                        __assign_46076
                      )'''
    new_assign = '''                      | "=" -> let expectedTyName = ref ("" : string) in (
                        ignore (let resolved = mapGetRaw (Obj.repr tyCtx) (name : string) in if resolved == Obj.magic (HxRuntime.hx_null) then let hinted = Obj.magic (HxMap.get_string localHints name) in if hinted == Obj.magic (HxRuntime.hx_null) then let __assign_bootstrap_int64_expected_1 = ("" : string) in (
                          expectedTyName := __assign_bootstrap_int64_expected_1;
                          __assign_bootstrap_int64_expected_1
                        ) else let __assign_bootstrap_int64_expected_2 = (TyType.toString (Obj.magic hinted) () : string) in (
                          expectedTyName := __assign_bootstrap_int64_expected_2;
                          __assign_bootstrap_int64_expected_2
                        ) else let __assign_bootstrap_int64_expected_3 = (TyType.toString (Obj.magic resolved) () : string) in (
                          expectedTyName := __assign_bootstrap_int64_expected_3;
                          __assign_bootstrap_int64_expected_3
                        ));
                        if HxString.equals (!expectedTyName) "Int64" || HxString.equals (!expectedTyName) "haxe.Int64" then let int64Operand = fun e -> let tempInt64Operand = ref ("" : string) in (
                          ignore (match e with
                            | HxExpr.EInt _p3 -> let _g_bootstrap_int64_operand = _p3 in let v = _g_bootstrap_int64_operand in let __assign_bootstrap_int64_operand_1 = (("Haxe_Int64.ofInt (" ^ HxString.toStdString (string_of_int v)) ^ ")" : string) in (
                              tempInt64Operand := __assign_bootstrap_int64_operand_1;
                              __assign_bootstrap_int64_operand_1
                            )
                            | HxExpr.EUnop (_p3, _p4) -> let _g_bootstrap_int64_operand_op = (_p3 : string) in let _g_bootstrap_int64_operand_inner = Obj.magic _p4 in if HxString.equals _g_bootstrap_int64_operand_op "-" then (match _g_bootstrap_int64_operand_inner with
                              | HxExpr.EInt _p5 -> let _g_bootstrap_int64_operand_v = _p5 in let v = _g_bootstrap_int64_operand_v in let __assign_bootstrap_int64_operand_2 = ((("Haxe_Int64.ofInt ((HxInt.neg (" ^ HxString.toStdString (string_of_int v)) ^ ")))" : string)) in (
                                tempInt64Operand := __assign_bootstrap_int64_operand_2;
                                __assign_bootstrap_int64_operand_2
                              )
                              | _ -> let __assign_bootstrap_int64_operand_3 = Obj.magic (returnExprToOcaml (Obj.magic e) allowedValueIdentsForStmt (Obj.magic (Obj.magic (HxRuntime.hx_null))) (Obj.repr arityByIdent) (Obj.repr tyCtx) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee) : string) in (
                                tempInt64Operand := __assign_bootstrap_int64_operand_3;
                                __assign_bootstrap_int64_operand_3
                              )) else let __assign_bootstrap_int64_operand_4 = Obj.magic (returnExprToOcaml (Obj.magic e) allowedValueIdentsForStmt (Obj.magic (Obj.magic (HxRuntime.hx_null))) (Obj.repr arityByIdent) (Obj.repr tyCtx) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee) : string) in (
                              tempInt64Operand := __assign_bootstrap_int64_operand_4;
                              __assign_bootstrap_int64_operand_4
                            )
                            | HxExpr.EIdent _p3 -> let _g_bootstrap_int64_operand_name = (_p3 : string) in let rhsName = (_g_bootstrap_int64_operand_name : string) in let rhsResolved = mapGetRaw (Obj.repr tyCtx) (rhsName : string) in if rhsResolved != Obj.magic (HxRuntime.hx_null) && HxString.equals (TyType.toString (Obj.magic rhsResolved) ()) "Int" then let __assign_bootstrap_int64_operand_5 = (("Haxe_Int64.ofInt (" ^ HxString.toStdString (ocamlReadValueIdent (rhsName : string))) ^ ")" : string) in (
                              tempInt64Operand := __assign_bootstrap_int64_operand_5;
                              __assign_bootstrap_int64_operand_5
                            ) else let __assign_bootstrap_int64_operand_6 = Obj.magic (returnExprToOcaml (Obj.magic e) allowedValueIdentsForStmt (Obj.magic (Obj.magic (HxRuntime.hx_null))) (Obj.repr arityByIdent) (Obj.repr tyCtx) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee) : string) in (
                              tempInt64Operand := __assign_bootstrap_int64_operand_6;
                              __assign_bootstrap_int64_operand_6
                            )
                            | _ -> let __assign_bootstrap_int64_operand_7 = Obj.magic (returnExprToOcaml (Obj.magic e) allowedValueIdentsForStmt (Obj.magic (Obj.magic (HxRuntime.hx_null))) (Obj.repr arityByIdent) (Obj.repr tyCtx) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee) : string) in (
                              tempInt64Operand := __assign_bootstrap_int64_operand_7;
                              __assign_bootstrap_int64_operand_7
                            ));
                          !tempInt64Operand
                        ) in (match rhs with
                          | HxExpr.EInt _p0 -> let _g_bootstrap_int64 = _p0 in let v = _g_bootstrap_int64 in let __assign_46076 = (("Haxe_Int64.ofInt (" ^ HxString.toStdString (string_of_int v)) ^ ")" : string) in (
                            tempMaybeString := __assign_46076;
                            __assign_46076
                          )
                          | HxExpr.EUnop (_p0, _p1) -> let _g_bootstrap_int64_op = (_p0 : string) in let _g_bootstrap_int64_inner = Obj.magic _p1 in if HxString.equals _g_bootstrap_int64_op "-" then (match _g_bootstrap_int64_inner with
                            | HxExpr.EInt _p2 -> let _g_bootstrap_int64_v = _p2 in let v = _g_bootstrap_int64_v in let __assign_46076 = ((("Haxe_Int64.ofInt ((HxInt.neg (" ^ HxString.toStdString (string_of_int v)) ^ ")))" : string)) in (
                              tempMaybeString := __assign_46076;
                              __assign_46076
                            )
                            | _ -> let __assign_46076 = Obj.magic (returnExprToOcaml (Obj.magic rhs) allowedValueIdentsForStmt (Obj.magic (Obj.magic (HxRuntime.hx_null))) (Obj.repr arityByIdent) (Obj.repr tyCtx) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee) : string) in (
                              tempMaybeString := __assign_46076;
                              __assign_46076
                            )) else let __assign_46076 = Obj.magic (returnExprToOcaml (Obj.magic rhs) allowedValueIdentsForStmt (Obj.magic (Obj.magic (HxRuntime.hx_null))) (Obj.repr arityByIdent) (Obj.repr tyCtx) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee) : string) in (
                            tempMaybeString := __assign_46076;
                            __assign_46076
                          )
                          | HxExpr.EBinop (_p0, _p1, _p2) -> let _g_bootstrap_int64_binop = (_p0 : string) in let left = Obj.magic _p1 in let right = Obj.magic _p2 in if HxString.equals _g_bootstrap_int64_binop "+" || HxString.equals _g_bootstrap_int64_binop "-" || HxString.equals _g_bootstrap_int64_binop "*" then let fn = if HxString.equals _g_bootstrap_int64_binop "+" then ("add" : string) else if HxString.equals _g_bootstrap_int64_binop "-" then ("sub" : string) else ("mul" : string) in let __assign_46076 = (((((("Haxe_Int64." ^ HxString.toStdString fn) ^ " (") ^ HxString.toStdString (int64Operand (Obj.magic left))) ^ ") (") ^ HxString.toStdString (int64Operand (Obj.magic right))) ^ ")" : string) in (
                            tempMaybeString := __assign_46076;
                            __assign_46076
                          ) else let __assign_46076 = Obj.magic (returnExprToOcaml (Obj.magic rhs) allowedValueIdentsForStmt (Obj.magic (Obj.magic (HxRuntime.hx_null))) (Obj.repr arityByIdent) (Obj.repr tyCtx) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee) : string) in (
                            tempMaybeString := __assign_46076;
                            __assign_46076
                          )
                          | _ -> let __assign_46076 = Obj.magic (returnExprToOcaml (Obj.magic rhs) allowedValueIdentsForStmt (Obj.magic (Obj.magic (HxRuntime.hx_null))) (Obj.repr arityByIdent) (Obj.repr tyCtx) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee) : string) in (
                            tempMaybeString := __assign_46076;
                            __assign_46076
                          )) else let __assign_46076 = Obj.magic (returnExprToOcaml (Obj.magic rhs) allowedValueIdentsForStmt (Obj.magic (Obj.magic (HxRuntime.hx_null))) (Obj.repr arityByIdent) (Obj.repr tyCtx) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee) : string) in (
                          tempMaybeString := __assign_46076;
                          __assign_46076
                        )
                      )'''

    patched_any = False

    if old_seed in src:
        src = src.replace(old_seed, new_seed, 1)
        patched_any = True
    else:
        seed_rx = re.compile(
            r'let existing = Obj\.magic \(HxMap\.get_string localHints name\) in let inferred = Obj\.magic \(\(!inferInitType\) '
            r'\(Obj\.obj \(HxEnum\.unbox_or_obj "HxExpr" init\)\) \(Obj\.magic \(HxRuntime\.hx_null\)\) \(Obj\.magic \(HxRuntime\.hx_null\)\)\) '
            r'in let existingNeedsUpgrade = existing == Obj\.magic \(HxRuntime\.hx_null\) \|\| TyType\.isUnknown \(Obj\.magic existing\) \(\) '
            r'\|\| HxString\.equals \(TyType\.toString \(Obj\.magic existing\) \(\)\) "Dynamic" \|\| HxString\.equals \(TyType\.toString \(Obj\.magic existing\) \(\)\) "Array" '
            r'in let inferredUseful = not \(TyType\.isUnknown \(Obj\.magic inferred\) \(\)\) && not \(HxString\.equals \(TyType\.toString \(Obj\.magic inferred\) \(\)\) "Dynamic"\) in if existingNeedsUpgrade && inferredUseful then ignore \(HxMap\.set_string localHints name inferred\) else \(\)'
        )
        src, seed_count = seed_rx.subn(new_seed, src, count=1)
        patched_any = patched_any or seed_count > 0

    if old_assign in src:
        src = src.replace(old_assign, new_assign, 1)
        patched_any = True
    else:
        assign_rx = re.compile(
            r'\| "=" -> let __assign_\d+ = Obj\.magic \(returnExprToOcaml \(Obj\.magic rhs\) allowedValueIdents(?:ForStmt)? '
            r'\(Obj\.magic \(Obj\.magic \(HxRuntime\.hx_null\)\)\) \(Obj\.repr arityByIdent\) \(Obj\.repr tyCtx\) '
            r'\(Obj\.repr staticImportByIdent\) \(currentPackagePath : string\) \(Obj\.repr moduleNameByPkgAndClass\) '
            r'\(Obj\.repr callSigByCallee\) : string\) in \(\n'
            r'\s*tempMaybeString := __assign_\d+;\n'
            r'\s*__assign_\d+\n'
            r'\s*\)'
        )
        src, assign_count = assign_rx.subn(new_assign, src, count=1)
        patched_any = patched_any or assign_count > 0

    old_expected_int64_anchor = '''  exprToOcaml (Obj.magic expr) (Obj.repr arityByIdent) (Obj.repr tyByIdent) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee)
) in Obj.magic __fallback_result_45804 with'''
    new_expected_int64_anchor = '''  ignore (if expectedReturnType != Obj.magic (HxRuntime.hx_null) && (HxString.equals (TyType.toString (Obj.magic expectedReturnType) ()) "Int64" || HxString.equals (TyType.toString (Obj.magic expectedReturnType) ()) "haxe.Int64") then ignore (let asInt64Value = fun e -> match e with
    | HxExpr.EInt _p0 -> let v = _p0 in Obj.repr ((("Haxe_Int64.ofInt (" ^ HxString.toStdString (string_of_int v)) ^ ")" : string))
    | HxExpr.EUnop (_p0, _p1) -> let _g_int64_op = (_p0 : string) in let _g_int64_inner = Obj.magic _p1 in if HxString.equals _g_int64_op "-" then (match _g_int64_inner with
      | HxExpr.EInt _p2 -> let v = _p2 in Obj.repr (((("Haxe_Int64.ofInt ((HxInt.neg (" ^ HxString.toStdString (string_of_int v)) ^ ")))" : string)))
      | _ -> Obj.magic (HxRuntime.hx_null)) else Obj.magic (HxRuntime.hx_null)
    | _ -> Obj.magic (HxRuntime.hx_null) in let asInt64Operand = fun e -> let direct = Obj.magic (asInt64Value (Obj.magic e)) in if direct != Obj.magic (HxRuntime.hx_null) then (Obj.obj direct : string) else (exprToOcaml (Obj.magic e) (Obj.repr arityByIdent) (Obj.repr tyByIdent) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee) : string) in let tempInt64Result = ref ("" : string) in (
    ignore (match expr with
      | HxExpr.EInt _ -> let direct = Obj.magic (asInt64Value (Obj.magic expr)) in (
        ignore (if direct != Obj.magic (HxRuntime.hx_null) then tempInt64Result := (Obj.obj direct : string) else ())
      )
      | HxExpr.EUnop (_p0, _p1) -> let op = (_p0 : string) in ignore (if HxString.equals op "-" then let direct = Obj.magic (asInt64Value (Obj.magic expr)) in (
        ignore (if direct != Obj.magic (HxRuntime.hx_null) then tempInt64Result := (Obj.obj direct : string) else ())
      ) else ())
      | HxExpr.EBinop (_p0, _p1, _p2) -> let op = (_p0 : string) in let left = Obj.magic _p1 in let right = Obj.magic _p2 in ignore (if HxString.equals op "+" || HxString.equals op "-" || HxString.equals op "*" then let fn = if HxString.equals op "+" then ("add" : string) else if HxString.equals op "-" then ("sub" : string) else ("mul" : string) in (
        tempInt64Result := (((((("Haxe_Int64." ^ HxString.toStdString fn) ^ " (") ^ HxString.toStdString (asInt64Operand (Obj.magic left))) ^ ") (") ^ HxString.toStdString (asInt64Operand (Obj.magic right))) ^ ")" : string)
      ) else ())
      | _ -> ());
    ignore (if HxString.length (!tempInt64Result) > 0 then raise (HxRuntime.Hx_return (Obj.repr (!tempInt64Result))) else ())
  )) else ());
  exprToOcaml (Obj.magic expr) (Obj.repr arityByIdent) (Obj.repr tyByIdent) (Obj.repr staticImportByIdent) (currentPackagePath : string) (Obj.repr moduleNameByPkgAndClass) (Obj.repr callSigByCallee)
) in Obj.magic __fallback_result_45804 with'''
    if old_expected_int64_anchor in src:
        src = src.replace(old_expected_int64_anchor, new_expected_int64_anchor, 1)
        patched_any = True

    if not patched_any:
        return

    write_text(path_str, src + "\n(* hxhx(stage3) bootstrap shim: mutable Int64 assignment repair *)\n")


def cmd_patch_int64_mixed_binops(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-int64-mixed-binops <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    if (
        "__assign_bootstrap_int64_operand_1" in src
        or "bootstrap shim: Int64 mixed-binop repair" in src
    ):
        write_text(path_str, src)
        return

    if "currentAllowedValueIdentNames" not in src and "tyForIdent = fun name" not in src and '| "%" | "*" | "-"' not in src:
        return

    src = replace_one(
        src,
        'let currentAllowedValueIdentNames = ref (Obj.magic (HxRuntime.hx_null) : bool HxMap.string_map)\n',
        'let currentAllowedValueIdentNames = ref (Obj.magic (HxRuntime.hx_null) : bool HxMap.string_map)\n'
        'let currentExprTyHints = ref (Obj.magic (HxRuntime.hx_null) : TyType.t HxMap.string_map)\n',
        "build-hxhx: failed to locate bootstrap currentAllowedValueIdentNames anchor for Int64 mixed-binop repair\n",
    )

    old_ty_for_ident_pattern = re.compile(
        r"""let tyForIdent = fun name -> try let __fallback_result_(?P<idx>\d+) = let resolved = \(getTyIdentRaw \(resolveTyIdentName \(name : string\)\) : Obj\.t\) in \(
  ignore \(if resolved == Obj\.magic \(HxRuntime\.hx_null\) then raise \(HxRuntime\.Hx_return \(Obj\.repr \(""\s*: string\)\)\) else \(\)\);
  let t = Obj\.magic resolved in \(
    ignore \(if t == Obj\.magic \(HxRuntime\.hx_null\) then raise \(HxRuntime\.Hx_return \(Obj\.repr \(""\s*: string\)\)\) else \(\)\);
    TyType\.toString \(Obj\.magic t\) \(\)
  \)
\) in Obj\.magic __fallback_result_(?P=idx) with""",
        re.S,
    )

    old_raw_ty_for_ident_pattern = re.compile(
        r"""let tyForIdent = fun name -> try let __fallback_result_(?P<idx>\d+) = let (?P<temp>tempString\d+) = ref \("" : string\) in \(
  ignore \(if mapGetRaw \(Obj\.repr tyByIdent\) \(name : string\) != Obj\.magic \(HxRuntime\.hx_null\) then let __assign_(?P<a>\d+) = \(name : string\) in \(
    (?P=temp) := __assign_(?P=a);
    __assign_(?P=a)
  \) else let lowered = \(ocamlValueIdent \(name : string\) : string\) in if not \(HxString\.equals lowered name\) && mapGetRaw \(Obj\.repr tyByIdent\) \(lowered : string\) != Obj\.magic \(HxRuntime\.hx_null\) then let __assign_(?P<b>\d+) = \(lowered : string\) in \(
    (?P=temp) := __assign_(?P=b);
    __assign_(?P=b)
  \) else let __assign_(?P<c>\d+) = \(name : string\) in \(
    (?P=temp) := __assign_(?P=c);
    __assign_(?P=c)
  \)\);
  let resolved = mapGetRaw \(Obj\.repr tyByIdent\) \(!(?P=temp) : string\) in \(
    ignore \(if resolved == Obj\.magic \(HxRuntime\.hx_null\) then raise \(HxRuntime\.Hx_return \(Obj\.repr \("" : string\)\)\) else \(\)\);
    let t = Obj\.magic resolved in \(
      ignore \(if t == Obj\.magic \(HxRuntime\.hx_null\) then raise \(HxRuntime\.Hx_return \(Obj\.repr \("" : string\)\)\) else \(\)\);
      TyType\.toString \(Obj\.magic t\) \(\)
    \)
  \)
\) in Obj\.magic __fallback_result_(?P=idx) with""",
        re.S,
    )
    hybrid_ty_for_ident_pattern = re.compile(
        r"""let tyForIdent = fun name -> try let __fallback_result_(?P<idx>\d+) = let (?P<temp>tempString\d+) = ref \("" : string\) in \(
  ignore \(if typedMapGet (?:tyByIdent|\(Obj\.repr tyByIdent\)) \(name : string\) != Obj\.magic \(HxRuntime\.hx_null\) then let __assign_(?P<a>\d+) = \(name : string\) in \(
    (?P=temp) := __assign_(?P=a);
    __assign_(?P=a)
  \) else let lowered = \(ocamlValueIdent \(name : string\) : string\) in if not \(HxString\.equals lowered name\) && typedMapGet (?:tyByIdent|\(Obj\.repr tyByIdent\)) \(lowered : string\) != Obj\.magic \(HxRuntime\.hx_null\) then let __assign_(?P<b>\d+) = \(lowered : string\) in \(
    (?P=temp) := __assign_(?P=b);
    __assign_(?P=b)
  \) else let __assign_(?P<c>\d+) = \(name : string\) in \(
    (?P=temp) := __assign_(?P=c);
    __assign_(?P=c)
  \)\);
  let resolved = mapGetRaw \(Obj\.repr tyByIdent\) \(!(?P=temp) : string\) in \(
    ignore \(if resolved == Obj\.magic \(HxRuntime\.hx_null\) then raise \(HxRuntime\.Hx_return \(Obj\.repr \("" : string\)\)\) else \(\)\);
    let t = Obj\.magic resolved in \(
      ignore \(if t == Obj\.magic \(HxRuntime\.hx_null\) then raise \(HxRuntime\.Hx_return \(Obj\.repr \("" : string\)\)\) else \(\)\);
      TyType\.toString \(Obj\.magic t\) \(\)
    \)
  \)
\) in Obj\.magic __fallback_result_(?P=idx) with""",
        re.S,
    )
    ty_match = old_ty_for_ident_pattern.search(src)
    raw_ty_match = None if ty_match is not None else old_raw_ty_for_ident_pattern.search(src)
    hybrid_ty_match = None if ty_match is not None or raw_ty_match is not None else hybrid_ty_for_ident_pattern.search(src)
    if ty_match is not None:
        idx = ty_match.group("idx")
        new_ty_for_ident = f'''let tyForIdent = fun name -> try let __fallback_result_{idx} = let resolvedName = (resolveTyIdentName (name : string) : string) in let tempResolvedTy = ref (Obj.magic (HxRuntime.hx_null) : Obj.t) in (
  ignore (let direct = (getTyIdentRaw (resolvedName : string) : Obj.t) in if direct == Obj.magic (HxRuntime.hx_null) && !currentExprTyHints != Obj.magic (HxRuntime.hx_null) then let fallback = Obj.magic (HxMap.get_string (!currentExprTyHints) resolvedName) in (
    tempResolvedTy := fallback;
    fallback
  ) else let __assign_bootstrap_expr_ty_1 = direct in (
    tempResolvedTy := __assign_bootstrap_expr_ty_1;
    __assign_bootstrap_expr_ty_1
  ));
  ignore (if !tempResolvedTy == Obj.magic (HxRuntime.hx_null) then raise (HxRuntime.Hx_return (Obj.repr ("" : string))) else ());
  let t = Obj.magic (!tempResolvedTy) in (
    ignore (if t == Obj.magic (HxRuntime.hx_null) then raise (HxRuntime.Hx_return (Obj.repr ("" : string))) else ());
    TyType.toString (Obj.magic t) ()
  )
) in Obj.magic __fallback_result_{idx} with'''
        src = src[:ty_match.start()] + new_ty_for_ident + src[ty_match.end():]
    elif raw_ty_match is not None:
        idx = raw_ty_match.group("idx")
        new_ty_for_ident = f'''let getTyIdentRaw = fun name -> let typedTyByIdent = Obj.magic tyByIdent in if typedTyByIdent == Obj.magic (HxRuntime.hx_null) then Obj.magic (HxRuntime.hx_null) else Obj.magic (HxMap.get_string typedTyByIdent name) in let resolveTyIdentName = fun name -> if getTyIdentRaw (name : string) != Obj.magic (HxRuntime.hx_null) then name else let lowered = (ocamlValueIdent (name : string) : string) in if not (HxString.equals lowered name) && getTyIdentRaw (lowered : string) != Obj.magic (HxRuntime.hx_null) then lowered else name in let tyForIdent = fun name -> try let __fallback_result_{idx} = let resolvedName = (resolveTyIdentName (name : string) : string) in let tempResolvedTy = ref (Obj.magic (HxRuntime.hx_null) : Obj.t) in (
  ignore (let direct = (getTyIdentRaw (resolvedName : string) : Obj.t) in if direct == Obj.magic (HxRuntime.hx_null) && !currentExprTyHints != Obj.magic (HxRuntime.hx_null) then let fallback = Obj.magic (HxMap.get_string (!currentExprTyHints) resolvedName) in (
    tempResolvedTy := fallback;
    fallback
  ) else let __assign_bootstrap_expr_ty_1 = direct in (
    tempResolvedTy := __assign_bootstrap_expr_ty_1;
    __assign_bootstrap_expr_ty_1
  ));
  ignore (if !tempResolvedTy == Obj.magic (HxRuntime.hx_null) then raise (HxRuntime.Hx_return (Obj.repr ("" : string))) else ());
  let t = Obj.magic (!tempResolvedTy) in (
    ignore (if t == Obj.magic (HxRuntime.hx_null) then raise (HxRuntime.Hx_return (Obj.repr ("" : string))) else ());
    TyType.toString (Obj.magic t) ()
  )
) in Obj.magic __fallback_result_{idx} with'''
        src = src[:raw_ty_match.start()] + new_ty_for_ident + src[raw_ty_match.end():]
    elif hybrid_ty_match is not None:
        idx = hybrid_ty_match.group("idx")
        new_ty_for_ident = f'''let getTyIdentRaw = fun name -> let typedTyByIdent = Obj.magic tyByIdent in if typedTyByIdent == Obj.magic (HxRuntime.hx_null) then Obj.magic (HxRuntime.hx_null) else Obj.magic (HxMap.get_string typedTyByIdent name) in let resolveTyIdentName = fun name -> if getTyIdentRaw (name : string) != Obj.magic (HxRuntime.hx_null) then name else let lowered = (ocamlValueIdent (name : string) : string) in if not (HxString.equals lowered name) && getTyIdentRaw (lowered : string) != Obj.magic (HxRuntime.hx_null) then lowered else name in let tyForIdent = fun name -> try let __fallback_result_{idx} = let resolvedName = (resolveTyIdentName (name : string) : string) in let tempResolvedTy = ref (Obj.magic (HxRuntime.hx_null) : Obj.t) in (
  ignore (let direct = (getTyIdentRaw (resolvedName : string) : Obj.t) in if direct == Obj.magic (HxRuntime.hx_null) && !currentExprTyHints != Obj.magic (HxRuntime.hx_null) then let fallback = Obj.magic (HxMap.get_string (!currentExprTyHints) resolvedName) in (
    tempResolvedTy := fallback;
    fallback
  ) else let __assign_bootstrap_expr_ty_1 = direct in (
    tempResolvedTy := __assign_bootstrap_expr_ty_1;
    __assign_bootstrap_expr_ty_1
  ));
  ignore (if !tempResolvedTy == Obj.magic (HxRuntime.hx_null) then raise (HxRuntime.Hx_return (Obj.repr ("" : string))) else ());
  let t = Obj.magic (!tempResolvedTy) in (
    ignore (if t == Obj.magic (HxRuntime.hx_null) then raise (HxRuntime.Hx_return (Obj.repr ("" : string))) else ());
    TyType.toString (Obj.magic t) ()
  )
) in Obj.magic __fallback_result_{idx} with'''
        src = src[:hybrid_ty_match.start()] + new_ty_for_ident + src[hybrid_ty_match.end():]
    elif "let resolvedName = (resolveTyIdentName (name : string) : string)" in src and "currentExprTyHints" in src:
        pass
    else:
        fail("build-hxhx: failed to locate bootstrap tyForIdent anchor for Int64 mixed-binop repair\n")

    eident_allowed_fallback = '''else if hasAllowedValueIdent (name : string) then let __assign_bootstrap_allowed_ident = (ocamlReadValueIdent (name : string) : string) in (
                                tempResult14 := __assign_bootstrap_allowed_ident;
                                __assign_bootstrap_allowed_ident
                              ) else if mapHasRaw (Obj.repr arityByIdent) (name : string) then'''
    if eident_allowed_fallback not in src:
        eident_allowed_pattern = re.compile(
            r"""\) else if isMutableLocalRefIdent \(name : string\) then let __assign_(?P<a>\d+) = \(ocamlReadValueIdent \(name : string\) : string\) in \(
\s+tempResult14 := __assign_(?P=a);
\s+__assign_(?P=a)
\s+\) else if mapHasRaw \(Obj\.repr arityByIdent\) \(name : string\) then""",
            re.S,
        )
        eident_allowed_match = eident_allowed_pattern.search(src)
        if eident_allowed_match is None:
            fail("build-hxhx: failed to locate bootstrap EIdent allowed-value anchor for Int64 mixed-binop repair\n")
        src = (
            src[:eident_allowed_match.start()]
            + eident_allowed_match.group(0).replace(
                ") else if mapHasRaw (Obj.repr arityByIdent) (name : string) then",
                ") else if hasAllowedValueIdent (name : string) then let __assign_bootstrap_allowed_ident = (ocamlReadValueIdent (name : string) : string) in (\n"
                "                                tempResult14 := __assign_bootstrap_allowed_ident;\n"
                "                                __assign_bootstrap_allowed_ident\n"
                "                              ) else if mapHasRaw (Obj.repr arityByIdent) (name : string) then",
                1,
            )
            + src[eident_allowed_match.end():]
        )

    old_stmt_intro = '''fun s tyCtx allowedValueIdentsForStmt -> let prevAllowedValueIdentNamesStmt = (!currentAllowedValueIdentNames : bool HxMap.string_map) in let _bootstrap_stmt_allowed_assign = let __assign_bootstrap_stmt_allowed_names = Obj.magic allowedValueIdentsForStmt in (
                      currentAllowedValueIdentNames := __assign_bootstrap_stmt_allowed_names;
                      __assign_bootstrap_stmt_allowed_names
                    ) in let tempResult6 = ref ("" : string) in (
                      ignore _bootstrap_stmt_allowed_assign;'''
    new_stmt_intro = '''fun s tyCtx allowedValueIdentsForStmt -> let prevAllowedValueIdentNamesStmt = (!currentAllowedValueIdentNames : bool HxMap.string_map) in let prevExprTyHintsStmt = (!currentExprTyHints : TyType.t HxMap.string_map) in let _bootstrap_stmt_allowed_assign = let __assign_bootstrap_stmt_allowed_names = Obj.magic allowedValueIdentsForStmt in (
                      currentAllowedValueIdentNames := __assign_bootstrap_stmt_allowed_names;
                      __assign_bootstrap_stmt_allowed_names
                    ) in let _bootstrap_expr_ty_hints_assign = let __assign_bootstrap_expr_ty_hints = Obj.magic localHints in (
                      currentExprTyHints := __assign_bootstrap_expr_ty_hints;
                      __assign_bootstrap_expr_ty_hints
                    ) in let tempResult6 = ref ("" : string) in (
                      ignore _bootstrap_stmt_allowed_assign;
                      ignore _bootstrap_expr_ty_hints_assign;'''
    if old_stmt_intro in src:
        src = replace_one(
            src,
            old_stmt_intro,
            new_stmt_intro,
            "build-hxhx: failed to locate bootstrap stmtToUnit intro anchor for Int64 mixed-binop repair\n",
        )

        old_stmt_restore = '''let __stmt_result = (!tempResult6 : string) in (
                        ignore (let __assign_bootstrap_restore_stmt_allowed = prevAllowedValueIdentNamesStmt in (
                          currentAllowedValueIdentNames := __assign_bootstrap_restore_stmt_allowed;
                          __assign_bootstrap_restore_stmt_allowed
                        ));
                        __stmt_result
                      )'''
        new_stmt_restore = '''let __stmt_result = (!tempResult6 : string) in (
                        ignore (let __assign_bootstrap_restore_stmt_allowed = prevAllowedValueIdentNamesStmt in (
                          currentAllowedValueIdentNames := __assign_bootstrap_restore_stmt_allowed;
                          __assign_bootstrap_restore_stmt_allowed
                        ));
                        ignore (let __assign_bootstrap_restore_expr_ty_hints = prevExprTyHintsStmt in (
                          currentExprTyHints := __assign_bootstrap_restore_expr_ty_hints;
                          __assign_bootstrap_restore_expr_ty_hints
                        ));
                        __stmt_result
                      )'''
        src = replace_one(
            src,
            old_stmt_restore,
            new_stmt_restore,
            "build-hxhx: failed to locate bootstrap stmtToUnit restore anchor for Int64 mixed-binop repair\n",
        )
    elif (
        "fun s tyCtx -> let tempResult6 = ref (\"\" : string) in (" in src
        or "fun s tyCtx -> let erasedTyCtx = Obj.repr tyCtx in let tempResult6 = ref (\"\" : string) in (" in src
    ):
        stmt_intro_pattern = re.compile(
            r"fun s tyCtx -> (?:(let erasedTyCtx = Obj\.repr tyCtx in )?)let tempResult6 = ref \(\"\" : string\) in \(\n\s+ignore \(match s with",
            re.S,
        )
        stmt_intro_match = stmt_intro_pattern.search(src)
        if stmt_intro_match is None:
            fail("build-hxhx: failed to locate bootstrap stmtToUnit intro anchor for Int64 mixed-binop repair\n")
        has_erased_tyctx = "let erasedTyCtx = Obj.repr tyCtx in" in stmt_intro_match.group(0)
        stmt_intro_replacement = '''fun s tyCtx -> let prevAllowedValueIdentNamesStmt = (!currentAllowedValueIdentNames : bool HxMap.string_map) in let prevExprTyHintsStmt = (!currentExprTyHints : TyType.t HxMap.string_map) in let _bootstrap_stmt_allowed_assign = let __assign_bootstrap_stmt_allowed_names = Obj.magic allowedValueIdents in (
                      currentAllowedValueIdentNames := __assign_bootstrap_stmt_allowed_names;
                      __assign_bootstrap_stmt_allowed_names
                    ) in let _bootstrap_expr_ty_hints_assign = let __assign_bootstrap_expr_ty_hints = Obj.magic localHints in (
                      currentExprTyHints := __assign_bootstrap_expr_ty_hints;
                      __assign_bootstrap_expr_ty_hints
                    ) in '''
        if has_erased_tyctx:
            stmt_intro_replacement += '''let erasedTyCtx = Obj.repr tyCtx in '''
        stmt_intro_replacement += '''let tempResult6 = ref ("" : string) in (
                      ignore _bootstrap_stmt_allowed_assign;
                      ignore _bootstrap_expr_ty_hints_assign;
                      ignore (match s with'''
        src = src[:stmt_intro_match.start()] + stmt_intro_replacement + src[stmt_intro_match.end():]

        stmt_restore_pattern = re.compile(
            r"\)\);\n\s+!tempResult6\n\s+\)\) in \(",
            re.S,
        )
        stmt_restore_match = stmt_restore_pattern.search(src, stmt_intro_match.start())
        if stmt_restore_match is None:
            fail("build-hxhx: failed to locate bootstrap stmtToUnit restore anchor for Int64 mixed-binop repair\n")
        stmt_restore_replacement = '''
                        ));
                      let __stmt_result = (!tempResult6 : string) in (
                        ignore (let __assign_bootstrap_restore_stmt_allowed = prevAllowedValueIdentNamesStmt in (
                          currentAllowedValueIdentNames := __assign_bootstrap_restore_stmt_allowed;
                          __assign_bootstrap_restore_stmt_allowed
                        ));
                        ignore (let __assign_bootstrap_restore_expr_ty_hints = prevExprTyHintsStmt in (
                          currentExprTyHints := __assign_bootstrap_restore_expr_ty_hints;
                          __assign_bootstrap_restore_expr_ty_hints
                        ));
                        __stmt_result
                      )
                    )) in ('''
        src = src[:stmt_restore_match.start()] + stmt_restore_replacement + src[stmt_restore_match.end():]
    else:
        fail("build-hxhx: failed to locate bootstrap stmtToUnit intro anchor for Int64 mixed-binop repair\n")

    int64_helper_ml = '''let isInt64TypeText = fun t -> HxString.equals t "Int64" || HxString.equals t "haxe.Int64" in let rec isInt64Expr = fun expr -> match expr with
                              | HxExpr.EIdent _p0 -> let _g_int64_ident = (_p0 : string) in isInt64TypeText (tyForIdent (_g_int64_ident : string))
                              | HxExpr.ECall (_p0, _p1) -> let _g_int64_callee = Obj.magic _p0 in (
                                ignore _p1;
                                match _g_int64_callee with
                                | HxExpr.EField (_p2, _p3) -> let _g_int64_owner_expr = Obj.magic _p2 in let _g_int64_field = (_p3 : string) in (match _g_int64_owner_expr with
                                  | HxExpr.EIdent _p4 -> let _g_int64_owner = (_p4 : string) in ((HxString.equals _g_int64_field "ofInt" || HxString.equals _g_int64_field "make") && (HxString.equals _g_int64_owner "Int64" || HxString.equals _g_int64_owner "haxe.Int64"))
                                  | _ -> false)
                                | _ -> false)
                              | HxExpr.ECast (_p0, _p1) -> let _g_int64_inner = Obj.magic _p0 in (
                                ignore (_p1 : string);
                                isInt64Expr (Obj.magic _g_int64_inner))
                              | HxExpr.EUntyped _p0 -> let _g_int64_inner = Obj.magic _p0 in isInt64Expr (Obj.magic _g_int64_inner)
                              | HxExpr.EUnop (_p0, _p1) -> let _g_int64_inner = Obj.magic _p1 in isInt64Expr (Obj.magic _g_int64_inner)
                              | HxExpr.EBinop (_p0, _p1, _p2) -> let _g_int64_op = (_p0 : string) in let _g_int64_left = Obj.magic _p1 in let _g_int64_right = Obj.magic _p2 in if HxString.equals _g_int64_op "+" || HxString.equals _g_int64_op "-" || HxString.equals _g_int64_op "*" then isInt64Expr (Obj.magic _g_int64_left) || isInt64Expr (Obj.magic _g_int64_right) else false
                              | _ -> false in let rec exprToOcamlAsInt64Operand = fun expr -> match expr with
                              | HxExpr.EInt _p0 -> let _g_int64_value = _p0 in (("Haxe_Int64.ofInt (" ^ HxString.toStdString (string_of_int _g_int64_value)) ^ ")" : string)
                              | HxExpr.ECast (_p0, _p1) -> let _g_int64_inner = Obj.magic _p0 in (
                                ignore (_p1 : string);
                                exprToOcamlAsInt64Operand (Obj.magic _g_int64_inner))
                              | HxExpr.EUntyped _p0 -> let _g_int64_inner = Obj.magic _p0 in exprToOcamlAsInt64Operand (Obj.magic _g_int64_inner)
                              | HxExpr.EUnop (_p0, _p1) -> let _g_int64_unop = (_p0 : string) in let _g_int64_inner = Obj.magic _p1 in if HxString.equals _g_int64_unop "-" then (match _g_int64_inner with
                                | HxExpr.EInt _p2 -> let _g_int64_value = _p2 in ((("Haxe_Int64.ofInt ((HxInt.neg (" ^ HxString.toStdString (string_of_int _g_int64_value)) ^ ")))" : string))
                                | _ -> (exprToOcaml (Obj.magic expr) arityByIdent tyByIdent staticImportByIdent (currentPackagePath : string) moduleNameByPkgAndClass callSigByCallee : string)) else (exprToOcaml (Obj.magic expr) arityByIdent tyByIdent staticImportByIdent (currentPackagePath : string) moduleNameByPkgAndClass callSigByCallee : string)
                              | HxExpr.EIdent _p0 -> let _g_int64_name = (_p0 : string) in if HxString.equals (tyForIdent (_g_int64_name : string)) "Int" then (("Haxe_Int64.ofInt (" ^ HxString.toStdString (ocamlReadValueIdent (_g_int64_name : string))) ^ ")" : string) else (exprToOcaml (Obj.magic expr) arityByIdent tyByIdent staticImportByIdent (currentPackagePath : string) moduleNameByPkgAndClass callSigByCallee : string)
                              | _ -> (exprToOcaml (Obj.magic expr) arityByIdent tyByIdent staticImportByIdent (currentPackagePath : string) moduleNameByPkgAndClass callSigByCallee : string) in '''

    old_minus_prefix = '''| "%" | "*" | "-" -> let aIsF = (!isFloatExpr) (Obj.magic a) in let bIsF = (!isFloatExpr) (Obj.magic b) in let aIsI = (!isIntExpr) (Obj.magic a) in let bIsI = (!isIntExpr) (Obj.magic b) in let hasKnownNumericSide = aIsF || bIsF || aIsI || bIsI in let allowNumericFallback = hasKnownNumericSide && not ((!isStringExpr) (Obj.magic a)) && not ((!isStringExpr) (Obj.magic b)) in let canFloat = HxString.equals op "+" || HxString.equals op "-" || HxString.equals op "*" || HxString.equals op "/" in if HxString.equals op "%" then'''
    new_minus_prefix = '''| "%" | "*" | "-" -> ''' + int64_helper_ml + '''if not (HxString.equals op "%") && (isInt64Expr (Obj.magic a) || isInt64Expr (Obj.magic b)) then let fn = if HxString.equals op "*" then ("mul" : string) else ("sub" : string) in (((((("Haxe_Int64." ^ HxString.toStdString fn) ^ " (") ^ HxString.toStdString (exprToOcamlAsInt64Operand (Obj.magic a))) ^ ") (") ^ HxString.toStdString (exprToOcamlAsInt64Operand (Obj.magic b))) ^ ")" : string) else let aIsF = (!isFloatExpr) (Obj.magic a) in let bIsF = (!isFloatExpr) (Obj.magic b) in let aIsI = (!isIntExpr) (Obj.magic a) in let bIsI = (!isIntExpr) (Obj.magic b) in let hasKnownNumericSide = aIsF || bIsF || aIsI || bIsI in let allowNumericFallback = hasKnownNumericSide && not ((!isStringExpr) (Obj.magic a)) && not ((!isStringExpr) (Obj.magic b)) in let canFloat = HxString.equals op "+" || HxString.equals op "-" || HxString.equals op "*" || HxString.equals op "/" in if HxString.equals op "%" then'''
    if old_minus_prefix in src:
        src = replace_one(
            src,
            old_minus_prefix,
            new_minus_prefix,
            "build-hxhx: failed to locate bootstrap Int64 mixed-binop (*,-,%) anchor\n",
        )
    elif "isInt64Expr" not in src:
        minus_pattern = re.compile(
            r"""\| "%" \| "\*" \| "-" -> let aIsF = \(!isFloatExpr\) \(Obj\.magic a\) in let bIsF = \(!isFloatExpr\) \(Obj\.magic b\) in let aIsI = \(!isIntExpr\) \(Obj\.magic a\) in let bIsI = \(!isIntExpr\) \(Obj\.magic b\) in let hasKnownNumericSide = aIsF \|\| bIsF \|\| aIsI \|\| bIsI in let allowNumericFallback = hasKnownNumericSide && not \(\(!isStringExpr\) \(Obj\.magic a\)\) && not \(\(!isStringExpr\) \(Obj\.magic b\)\) in let canFloat = HxString\.equals op "\+" \|\| HxString\.equals op "-" \|\| HxString\.equals op "\*" \|\| HxString\.equals op "/" in if HxString\.equals op "%" then""",
            re.S,
        )
        src, count = minus_pattern.subn(new_minus_prefix, src, count=1)
        if count == 0:
            fail("build-hxhx: failed to locate bootstrap Int64 mixed-binop (*,-,%) anchor\n")

    old_plus_prefix = '''| "+" -> if (!isStringExpr) (Obj.magic a) || (!isStringExpr) (Obj.magic b) then let __assign_45646 = (((("((" ^ HxString.toStdString (exprToOcamlForConcat (Obj.magic a))) ^ ") ^ (") ^ HxString.toStdString (exprToOcamlForConcat (Obj.magic b))) ^ "))" : string) in (
                                tempResult13 := __assign_45646;
                                __assign_45646
                              ) else let aIsF = (!isFloatExpr) (Obj.magic a) in let bIsF = (!isFloatExpr) (Obj.magic b) in let aIsI = (!isIntExpr) (Obj.magic a) in let bIsI = (!isIntExpr) (Obj.magic b) in let hasKnownNumericSide = aIsF || bIsF || aIsI || bIsI in let allowNumericFallback = hasKnownNumericSide && not ((!isStringExpr) (Obj.magic a)) && not ((!isStringExpr) (Obj.magic b)) in let canFloat = HxString.equals op "+" || HxString.equals op "-" || HxString.equals op "*" || HxString.equals op "/" in if HxString.equals op "%" then'''
    new_plus_prefix = '''| "+" -> if (!isStringExpr) (Obj.magic a) || (!isStringExpr) (Obj.magic b) then (((("((" ^ HxString.toStdString (exprToOcamlForConcat (Obj.magic a))) ^ ") ^ (") ^ HxString.toStdString (exprToOcamlForConcat (Obj.magic b))) ^ "))" : string) else ''' + int64_helper_ml + '''if isInt64Expr (Obj.magic a) || isInt64Expr (Obj.magic b) then ((((("Haxe_Int64.add (" ^ HxString.toStdString (exprToOcamlAsInt64Operand (Obj.magic a))) ^ ") (") ^ HxString.toStdString (exprToOcamlAsInt64Operand (Obj.magic b))) ^ ")" : string)) else let aIsF = (!isFloatExpr) (Obj.magic a) in let bIsF = (!isFloatExpr) (Obj.magic b) in let aIsI = (!isIntExpr) (Obj.magic a) in let bIsI = (!isIntExpr) (Obj.magic b) in let hasKnownNumericSide = aIsF || bIsF || aIsI || bIsI in let allowNumericFallback = hasKnownNumericSide && not ((!isStringExpr) (Obj.magic a)) && not ((!isStringExpr) (Obj.magic b)) in let canFloat = HxString.equals op "+" || HxString.equals op "-" || HxString.equals op "*" || HxString.equals op "/" in if HxString.equals op "%" then'''
    if old_plus_prefix in src:
        src = replace_one(
            src,
            old_plus_prefix,
            new_plus_prefix,
            "build-hxhx: failed to locate bootstrap Int64 mixed-binop (+) anchor\n",
        )
    elif "isInt64Expr" not in src:
        plus_pattern = re.compile(
            r"""\| "\+" -> if \(!isStringExpr\) \(Obj\.magic a\) \|\| \(!isStringExpr\) \(Obj\.magic b\) then let __assign_\d+ = \(\(\(\("\(\(" \^ HxString\.toStdString \(exprToOcamlForConcat \(Obj\.magic a\)\)\) \^ "\) \^ \(" \^ HxString\.toStdString \(exprToOcamlForConcat \(Obj\.magic b\)\)\) \^ "\)\)" : string\) in \(
\s+tempResult14 := __assign_\d+;
\s+__assign_\d+
\s+\) else let aIsF = \(!isFloatExpr\) \(Obj\.magic a\) in let bIsF = \(!isFloatExpr\) \(Obj\.magic b\) in let aIsI = \(!isIntExpr\) \(Obj\.magic a\) in let bIsI = \(!isIntExpr\) \(Obj\.magic b\) in let hasKnownNumericSide = aIsF \|\| bIsF \|\| aIsI \|\| bIsI in let allowNumericFallback = hasKnownNumericSide && not \(\(!isStringExpr\) \(Obj\.magic a\)\) && not \(\(!isStringExpr\) \(Obj\.magic b\)\) in let canFloat = HxString\.equals op "\+" \|\| HxString\.equals op "-" \|\| HxString\.equals op "\*" \|\| HxString\.equals op "/" in if HxString\.equals op "%" then""",
            re.S,
        )
        src, count = plus_pattern.subn(new_plus_prefix, src, count=1)
        if count == 0:
            fail("build-hxhx: failed to locate bootstrap Int64 mixed-binop (+) anchor\n")

    write_text(path_str, src + "\n(* hxhx(stage3) bootstrap shim: Int64 mixed-binop repair *)\n")


def cmd_patch_int64_static_helpers(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-int64-static-helpers <path>\n")
    path_str = argv[0]
    src = read_text(path_str)
    needle = '| "ofInt" -> if HxArray.length _g1 = 1'
    if needle not in src:
        return

    int64_operand_helper = '''let rec int64Operand = fun expr -> match expr with
                              | HxExpr.EInt _p0 -> let _g_int64_value = _p0 in (("Haxe_Int64.ofInt (" ^ HxString.toStdString (string_of_int _g_int64_value)) ^ ")" : string)
                              | HxExpr.ECast (_p0, _p1) -> let _g_int64_inner = Obj.magic _p0 in (
                                ignore (_p1 : string);
                                int64Operand (Obj.magic _g_int64_inner))
                              | HxExpr.EUntyped _p0 -> let _g_int64_inner = Obj.magic _p0 in int64Operand (Obj.magic _g_int64_inner)
                              | HxExpr.EUnop (_p0, _p1) -> let _g_int64_unop = (_p0 : string) in let _g_int64_inner = Obj.magic _p1 in if HxString.equals _g_int64_unop "-" then (match _g_int64_inner with
                                | HxExpr.EInt _p2 -> let _g_int64_value = _p2 in ((("Haxe_Int64.ofInt ((HxInt.neg (" ^ HxString.toStdString (string_of_int _g_int64_value)) ^ ")))" : string))
                                | _ -> (exprToOcaml (Obj.magic expr) arityByIdent tyByIdent staticImportByIdent (currentPackagePath : string) moduleNameByPkgAndClass (Obj.magic (HxRuntime.hx_null)) : string)) else (exprToOcaml (Obj.magic expr) arityByIdent tyByIdent staticImportByIdent (currentPackagePath : string) moduleNameByPkgAndClass (Obj.magic (HxRuntime.hx_null)) : string)
                              | HxExpr.EIdent _p0 -> let _g_int64_name = (_p0 : string) in if HxString.equals (tyForIdent (_g_int64_name : string)) "Int" then (("Haxe_Int64.ofInt (" ^ HxString.toStdString (ocamlReadValueIdent (_g_int64_name : string))) ^ ")" : string) else (exprToOcaml (Obj.magic expr) arityByIdent tyByIdent staticImportByIdent (currentPackagePath : string) moduleNameByPkgAndClass (Obj.magic (HxRuntime.hx_null)) : string)
                              | _ -> (exprToOcaml (Obj.magic expr) arityByIdent tyByIdent staticImportByIdent (currentPackagePath : string) moduleNameByPkgAndClass (Obj.magic (HxRuntime.hx_null)) : string) in '''

    int64_helper_block = '''| "add" -> if HxArray.length _g1 = 2 then let _g5 = Obj.magic (HxArray.get (Obj.magic _g1) 0) in let _g6 = Obj.magic (HxArray.get (Obj.magic _g1) 1) in let left = Obj.magic _g5 in let right = Obj.magic _g6 in ''' + int64_operand_helper + '''let leftCode = HxString.toStdString (int64Operand (Obj.magic left)) in let rightCode = HxString.toStdString (int64Operand (Obj.magic right)) in ((("Haxe_Int64.add (" ^ leftCode) ^ ") (") ^ rightCode) ^ ")" else "(Obj.magic 0)"
                              | "sub" -> if HxArray.length _g1 = 2 then let _g5 = Obj.magic (HxArray.get (Obj.magic _g1) 0) in let _g6 = Obj.magic (HxArray.get (Obj.magic _g1) 1) in let left = Obj.magic _g5 in let right = Obj.magic _g6 in ''' + int64_operand_helper + '''let leftCode = HxString.toStdString (int64Operand (Obj.magic left)) in let rightCode = HxString.toStdString (int64Operand (Obj.magic right)) in ((("Haxe_Int64.sub (" ^ leftCode) ^ ") (") ^ rightCode) ^ ")" else "(Obj.magic 0)"
                              | "mul" -> if HxArray.length _g1 = 2 then let _g5 = Obj.magic (HxArray.get (Obj.magic _g1) 0) in let _g6 = Obj.magic (HxArray.get (Obj.magic _g1) 1) in let left = Obj.magic _g5 in let right = Obj.magic _g6 in ''' + int64_operand_helper + '''let leftCode = HxString.toStdString (int64Operand (Obj.magic left)) in let rightCode = HxString.toStdString (int64Operand (Obj.magic right)) in ((("Haxe_Int64.mul (" ^ leftCode) ^ ") (") ^ rightCode) ^ ")" else "(Obj.magic 0)"
                              | "ofInt" -> if HxArray.length _g1 = 1'''

    src = src.replace(needle, int64_helper_block)
    write_text(path_str, src + "\n(* hxhx(stage3) bootstrap shim: Int64 static-helper repair *)\n")


def cmd_patch_plugin_dune_layout(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-plugin-dune-layout <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    # Newer regenerated snapshots carry the plugin dune layout in EmitterStage.hx source.
    # Keep this legacy patch as a no-op once the source-side implementation is present.
    if (
        "let emitPluginDuneLayoutIfRequestedForStage3 =" in src
        and "ocaml_dune_layout=plugin" in src
        and "out.cma" in src
    ):
        write_text(path_str, src)
        return

    needle = '                                  ignore (if not (buildExecutable) then raise (HxRuntime.Hx_return (Obj.repr (exePath : string))) else ());'
    replacement = '''                                  let bootstrapArgs = Obj.magic (HxSys.args ()) in let bootstrapWantsPluginDune = let rec loop idx sawPlugin = if idx >= HxArray.length bootstrapArgs then sawPlugin else let arg = (HxArray.get (Obj.magic bootstrapArgs) idx : string) in if HxString.equals arg "-D" && idx + 1 < HxArray.length bootstrapArgs then let value = (HxArray.get (Obj.magic bootstrapArgs) (idx + 1) : string) in loop (idx + 2) (sawPlugin || HxString.equals value "ocaml_dune_layout=plugin") else loop (idx + 1) sawPlugin in loop 0 false in
                                    ignore (if bootstrapWantsPluginDune then (
                                      let runtimeDunePath = Filename.concat (Filename.concat outAbs "runtime") "dune" in
                                      let duneProjectPath = Filename.concat outAbs "dune-project" in
                                      let dunePath = Filename.concat outAbs "dune" in
                                      let outMlPath = Filename.concat outAbs "out.ml" in
                                      let pluginArtifactPath = Filename.concat outAbs "out.cma" in
                                      ignore (HxFile.saveContent (runtimeDunePath : string) ("(library\n (name hx_runtime)\n (wrapped false)\n (modules :standard)\n (libraries unix str threads dynlink))\n\n; Generated by hxhx(stage3)\n" : string));
                                      ignore (HxFile.saveContent ((Filename.concat outAbs ".gitignore") : string) ("_build/\n*.install\n" : string));
                                      ignore (HxFile.saveContent (duneProjectPath : string) ("(lang dune 2.9)\n(name out)\n(wrapped_executables false)\n\n; Generated by hxhx(stage3)\n" : string));
                                      ignore (HxFile.saveContent (dunePath : string) ("(executable\n (name out)\n (modules :standard)\n (libraries hx_runtime unix str threads dynlink)\n (modes (native plugin) (byte plugin)))\n\n; Generated by hxhx(stage3)\n" : string));
                                      ignore (HxFile.saveContent (outMlPath : string) ("let () = ()\n" : string));
                                      raise (HxRuntime.Hx_return (Obj.repr (pluginArtifactPath : string)))
                                    ) else ());
                                    ignore (if not (buildExecutable) then raise (HxRuntime.Hx_return (Obj.repr (exePath : string))) else ());
                                    (* hxhx(stage3) bootstrap shim: plugin dune layout repair *)'''
    if needle not in src:
        fail("build-hxhx: failed to locate plugin dune layout repair anchor in EmitterStage.ml\n")
    write_text(path_str, src.replace(needle, replacement, 1))


def cmd_patch_js_target_core_native_js_lib_externs(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-js-target-core-native-js-lib-externs <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    # Newer regenerated bootstrap snapshots already carry the source-side native JS extern
    # lowering directly. In that case there is nothing left for this compatibility patch to
    # inject, so treat the helper as a no-op instead of failing on stale anchors.
    if (
        ((
            "let nativeJsGlobalExternRef = fun fullName ->" in src
            and "nativeJsGlobalExternRef (Obj.obj (HxAnon.get unit \"fullName\") : string)" in src
        ) or (
            "let nativeJsLibGlobalRef = fun fullName ->" in src
            and "nativeJsLibGlobalRef (Obj.obj (HxAnon.get unit \"fullName\") : string)" in src
        ))
        and "tempLeft <> emitNative" in src
    ):
        write_text(path_str, src)
        return

    old_var = '''  ignore (Backend_js_JsWriter.writeln (Obj.magic writer) (("var " ^ HxString.toStdString (Obj.obj (HxAnon.get unit "jsRef"))) ^ " = {};" : string));'''
    new_var = '''  ignore (
    if StringTools.startsWith ((Obj.obj (HxAnon.get unit "fullName") : string)) ("js.lib." : string) then (
      let nativeParts = HxString.split (HxString.substr (Obj.obj (HxAnon.get unit "fullName") : string) (HxString.length "js.lib.") (-1)) ("." : string) in
      let nativeExpr = ref ("globalThis" : string) in
      let nativeGuard = ref ("(globalThis != null)" : string) in (
        ignore (let _g_native = ref 0 in while !_g_native < HxArray.length nativeParts do ignore (let part = (HxArray.get (Obj.magic nativeParts) (!_g_native) : string) in (
          let partIndex = !_g_native in
          ignore (let __old_native = !_g_native in let __new_native = HxInt.add __old_native 1 in (
            ignore (_g_native := __new_native);
            __new_native
          ));
          ignore (if part == Obj.magic (HxRuntime.hx_null) || HxString.length part = 0 then () else (
            let globalPart = if partIndex = 0 && HxString.equals part "intl" then ("Intl" : string) else (part : string) in
            let __assign_native = ((((HxString.toStdString (!nativeExpr) ^ "[") ^ HxString.toStdString (Backend_js_JsNameMangler.quoteString (globalPart : string))) ^ "]") : string) in (
              nativeExpr := __assign_native;
              nativeGuard := ((((("(" ^ HxString.toStdString (!nativeGuard)) ^ " && ") ^ HxString.toStdString (!nativeExpr)) ^ " != null)") : string);
              ()
            )
          ))
        )) done);
        Backend_js_JsWriter.writeln (Obj.magic writer) (((((((("var " ^ HxString.toStdString (Obj.obj (HxAnon.get unit "jsRef"))) ^ " = (") ^ HxString.toStdString (!nativeGuard)) ^ " ? ") ^ HxString.toStdString (!nativeExpr)) ^ " : {})") ^ ";" : string))
      )
    ) else (
      Backend_js_JsWriter.writeln (Obj.magic writer) (("var " ^ HxString.toStdString (Obj.obj (HxAnon.get unit "jsRef"))) ^ " = {};" : string)
    )
  );
  (* hxhx(stage3) bootstrap shim: js.lib extern native global repair *)'''

    old_fields = '''      ignore (let _g = ref 0 in let _g1 = Obj.magic (HxClassDecl.getFields (Obj.magic (Obj.obj (HxAnon.get unit "decl")))) in try while !_g < HxArray.length _g1 do try ignore (let field = Obj.magic (HxArray.get (Obj.magic _g1) (!_g)) in ('''
    new_fields = '''      ignore (let _g = ref 0 in let _g1 = if StringTools.startsWith ((Obj.obj (HxAnon.get unit "fullName") : string)) ("js.lib." : string) then Obj.magic (let __arr_native_js_lib_fields = HxArray.create () in __arr_native_js_lib_fields) else Obj.magic (HxClassDecl.getFields (Obj.magic (Obj.obj (HxAnon.get unit "decl")))) in try while !_g < HxArray.length _g1 do try ignore (let field = Obj.magic (HxArray.get (Obj.magic _g1) (!_g)) in ('''

    old_functions = '''      let _g = ref 0 in let _g1 = Obj.magic (HxClassDecl.getFunctions (Obj.magic (Obj.obj (HxAnon.get unit "decl")))) in try while !_g < HxArray.length _g1 do try ignore (let fn = Obj.magic (HxArray.get (Obj.magic _g1) (!_g)) in ('''
    new_functions = '''      let _g = ref 0 in let _g1 = if StringTools.startsWith ((Obj.obj (HxAnon.get unit "fullName") : string)) ("js.lib." : string) then Obj.magic (let __arr_native_js_lib_functions = HxArray.create () in __arr_native_js_lib_functions) else Obj.magic (HxClassDecl.getFunctions (Obj.magic (Obj.obj (HxAnon.get unit "decl")))) in try while !_g < HxArray.length _g1 do try ignore (let fn = Obj.magic (HxArray.get (Obj.magic _g1) (!_g)) in ('''

    old_emit_loop = '''        let classRefs = Obj.magic (buildClassRefs (Obj.magic (Obj.obj (HxAnon.get classes "bySimpleName"))) (Obj.magic (Obj.obj (HxAnon.get classes "byFullName")))) in let _g = ref 0 in let _g1 = Obj.magic (Obj.obj (HxAnon.get classes "units")) in (
          ignore (while !_g < HxArray.length _g1 do ignore (let unit = HxArray.get (Obj.magic _g1) (!_g) in (
            ignore (let __old_4 = !_g in let __new_5 = HxInt.add __old_4 1 in (
              ignore (_g := __new_5);
              __new_5
            ));
            emitClass (Obj.magic writer) unit (Obj.magic classRefs) (Obj.magic (Obj.obj (HxAnon.get classes "bySimpleName")))
          )) done);
          let mainRef = (resolveMainRef ((Obj.magic context : Backend_BackendContext.t).mainModule : string) (Obj.magic (Obj.obj (HxAnon.get classes "bySimpleName"))) (Obj.magic (Obj.obj (HxAnon.get classes "byFullName"))) : string) in ('''

    new_emit_loop = '''        let classRefs = Obj.magic (buildClassRefs (Obj.magic (Obj.obj (HxAnon.get classes "bySimpleName"))) (Obj.magic (Obj.obj (HxAnon.get classes "byFullName")))) in let units = Obj.magic (Obj.obj (HxAnon.get classes "units")) in (
          ignore (try let _g_native = ref 0 in while !_g_native < HxArray.length units do try ignore (let unit = HxArray.get (Obj.magic units) (!_g_native) in (
            ignore (let __old_native_4 = !_g_native in let __new_native_5 = HxInt.add __old_native_4 1 in (
              ignore (_g_native := __new_native_5);
              __new_native_5
            ));
            ignore (if not (StringTools.startsWith ((Obj.obj (HxAnon.get unit "fullName") : string)) ("js.lib." : string)) then raise (HxRuntime.Hx_continue) else ());
            emitClass (Obj.magic writer) unit (Obj.magic classRefs) (Obj.magic (Obj.obj (HxAnon.get classes "bySimpleName")))
          )) with
            | HxRuntime.Hx_continue -> () done with
            | HxRuntime.Hx_break -> ());
          ignore (try let _g_other = ref 0 in while !_g_other < HxArray.length units do try ignore (let unit = HxArray.get (Obj.magic units) (!_g_other) in (
            ignore (let __old_other_4 = !_g_other in let __new_other_5 = HxInt.add __old_other_4 1 in (
              ignore (_g_other := __new_other_5);
              __new_other_5
            ));
            ignore (if StringTools.startsWith ((Obj.obj (HxAnon.get unit "fullName") : string)) ("js.lib." : string) then raise (HxRuntime.Hx_continue) else ());
            emitClass (Obj.magic writer) unit (Obj.magic classRefs) (Obj.magic (Obj.obj (HxAnon.get classes "bySimpleName")))
          )) with
            | HxRuntime.Hx_continue -> () done with
            | HxRuntime.Hx_break -> ());
          let mainRef = (resolveMainRef ((Obj.magic context : Backend_BackendContext.t).mainModule : string) (Obj.magic (Obj.obj (HxAnon.get classes "bySimpleName"))) (Obj.magic (Obj.obj (HxAnon.get classes "byFullName"))) : string) in ('''


    for old, new, label in (
        (old_var, new_var, "js lib var alias"),
        (old_fields, new_fields, "js lib static fields"),
        (old_functions, new_functions, "js lib static functions"),
        (old_emit_loop, new_emit_loop, "js lib emit order"),
    ):
        if old not in src:
            fail(f"build-hxhx: failed to locate bootstrap JsTargetCore {label} anchor\\n")
        src = src.replace(old, new, 1)

    write_text(path_str, src)


def cmd_patch_js_target_core_systools_static_bodies(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-js-target-core-systools-static-bodies <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    marker = "(* hxhx(stage3) bootstrap shim: js target core SysTools static bodies *)"
    if marker in src or "let emitKnownStaticFunctionBody = fun writer fullName fnName params ->" in src:
        write_text(path_str, src)
        return

    helper = r'''
let emitKnownStaticFunctionBody = fun writer fullName fnName params ->
  if not (HxString.equals fullName "haxe.SysTools") then false
  else if HxString.equals fnName "quoteUnixArg" then (
    if HxArray.length params < 1 then false
    else let argument = (HxArray.get (Obj.magic params) 0 : string) in (
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ((((HxString.toStdString argument ^ " = String(") ^ HxString.toStdString argument) ^ ");") : string));
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ((("if (" ^ HxString.toStdString argument) ^ " === \"\") return \"''\";") : string));
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) (((("if (!/[^a-zA-Z0-9_@%+=:,.\\/-]/.test(" ^ HxString.toStdString argument) ^ ")) return ") ^ HxString.toStdString argument) ^ ";" : string));
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ((("return \"'\" + " ^ HxString.toStdString argument) ^ ".split(\"'\").join(\"'\\\"'\\\"'\") + \"'\";") : string));
      true
    )
  ) else if HxString.equals fnName "quoteWinArg" then (
    if HxArray.length params < 2 then false
    else let argument = (HxArray.get (Obj.magic params) 0 : string) in let escapeMetaCharacters = (HxArray.get (Obj.magic params) 1 : string) in (
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ((((HxString.toStdString argument ^ " = String(") ^ HxString.toStdString argument) ^ ");") : string));
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ((("if (!/^(\\/)?[^ \\t\\/\\\\\"]+$/.test(" ^ HxString.toStdString argument) ^ ")) {") : string));
      ignore (Backend_js_JsWriter.pushIndent (Obj.magic writer) ());
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("var result = \"\";" : string));
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) (((((((("var needquote = " ^ HxString.toStdString argument) ^ ".indexOf(\" \") !== -1 || ") ^ HxString.toStdString argument) ^ ".indexOf(\"\\t\") !== -1 || ") ^ HxString.toStdString argument) ^ " === \"\" || ") ^ HxString.toStdString argument) ^ ".indexOf(\"/\") > 0;" : string));
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("if (needquote) result += \"\\\"\";" : string));
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("var bs = \"\";" : string));
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ((("for (var i = 0; i < " ^ HxString.toStdString argument) ^ ".length; i++) {") : string));
      ignore (Backend_js_JsWriter.pushIndent (Obj.magic writer) ());
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ((("var ch = " ^ HxString.toStdString argument) ^ ".charAt(i);") : string));
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("if (ch === \"\\\\\") {" : string));
      ignore (Backend_js_JsWriter.pushIndent (Obj.magic writer) ());
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("bs += \"\\\\\";" : string));
      ignore (Backend_js_JsWriter.popIndent (Obj.magic writer) ());
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("} else if (ch === \"\\\"\") {" : string));
      ignore (Backend_js_JsWriter.pushIndent (Obj.magic writer) ());
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("result += bs + bs + \"\\\\\\\"\";" : string));
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("bs = \"\";" : string));
      ignore (Backend_js_JsWriter.popIndent (Obj.magic writer) ());
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("} else {" : string));
      ignore (Backend_js_JsWriter.pushIndent (Obj.magic writer) ());
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("if (bs.length > 0) { result += bs; bs = \"\"; }" : string));
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("result += ch;" : string));
      ignore (Backend_js_JsWriter.popIndent (Obj.magic writer) ());
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("}" : string));
      ignore (Backend_js_JsWriter.popIndent (Obj.magic writer) ());
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("}" : string));
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("result += bs;" : string));
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("if (needquote) { result += bs; result += \"\\\"\"; }" : string));
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ((HxString.toStdString argument ^ " = result;") : string));
      ignore (Backend_js_JsWriter.popIndent (Obj.magic writer) ());
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("}" : string));
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ((("if (" ^ HxString.toStdString escapeMetaCharacters) ^ ") {") : string));
      ignore (Backend_js_JsWriter.pushIndent (Obj.magic writer) ());
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("var escaped = \"\";" : string));
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("var metas = \" ()%!^\\\"<>&|\\n\\r,;\";" : string));
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ((("for (var j = 0; j < " ^ HxString.toStdString argument) ^ ".length; j++) {") : string));
      ignore (Backend_js_JsWriter.pushIndent (Obj.magic writer) ());
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ((("var metaCh = " ^ HxString.toStdString argument) ^ ".charAt(j);") : string));
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("if (metas.indexOf(metaCh) >= 0) escaped += \"^\";" : string));
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("escaped += metaCh;" : string));
      ignore (Backend_js_JsWriter.popIndent (Obj.magic writer) ());
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("}" : string));
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("return escaped;" : string));
      ignore (Backend_js_JsWriter.popIndent (Obj.magic writer) ());
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ("}" : string));
      ignore (Backend_js_JsWriter.writeln (Obj.magic writer) ((("return " ^ HxString.toStdString argument) ^ ";") : string));
      true
    )
  ) else false

(* hxhx(stage3) bootstrap shim: js target core SysTools static bodies *)
'''

    src = replace_one(
        src,
        "\nlet emitClass = fun writer unit classRefs simpleNameRefs ->",
        "\n" + helper + "\nlet emitClass = fun writer unit classRefs simpleNameRefs ->",
        "build-hxhx: failed to locate bootstrap JsTargetCore SysTools helper anchor\n",
    )

    old_call = '''              ignore (try Backend_js_JsStmtEmitter.emitFunctionBody (Obj.magic writer) (Obj.magic (HxFunctionDecl.getBody (Obj.magic fn))) (Obj.magic fnScope) with'''
    new_call = '''              ignore (if not (emitKnownStaticFunctionBody (Obj.magic writer) (Obj.obj (HxAnon.get unit "fullName") : string) (HxFunctionDecl.getName (Obj.magic fn) : string) (Obj.magic params)) then try Backend_js_JsStmtEmitter.emitFunctionBody (Obj.magic writer) (Obj.magic (HxFunctionDecl.getBody (Obj.magic fn))) (Obj.magic fnScope) with'''
    src = replace_one(
        src,
        old_call,
        new_call,
        "build-hxhx: failed to locate bootstrap JsTargetCore static body emit anchor\n",
    )

    src = replace_one(
        src,
        "                ) else raise (__exn_47));",
        "                ) else raise (__exn_47) else ());",
        "build-hxhx: failed to locate bootstrap JsTargetCore static body emit close anchor\n",
    )
    write_text(path_str, src)


def cmd_patch_hxtype_registry_js_target_core_systools(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-hxtype-registry-js-target-core-systools <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    old = '''HxType.register_class_static_fields "backend.js.JsTargetCore" [ "allowStaticBodyFallback"; "buildClassRefs"; "collectClassUnits"; "emitBridge"; "emitClass"; "emitRuntimePrelude"; "ensureDirectory"; "isNativeJsLibExtern"; "nativeJsLibGlobalRef"; "resolveMainRef"; "simpleName" ]'''
    new = '''HxType.register_class_static_fields "backend.js.JsTargetCore" [ "allowStaticBodyFallback"; "buildClassRefs"; "collectClassUnits"; "emitBridge"; "emitClass"; "emitKnownStaticFunctionBody"; "emitRuntimePrelude"; "ensureDirectory"; "isNativeJsLibExtern"; "nativeJsLibGlobalRef"; "resolveMainRef"; "simpleName" ]'''
    if '"emitKnownStaticFunctionBody"' in src:
        write_text(path_str, src)
        return
    src = replace_one(
        src,
        old,
        new,
        "build-hxhx: failed to locate HxTypeRegistry JsTargetCore SysTools field anchor\n",
    )
    write_text(path_str, src)


def cmd_patch_typerstage_lowercase_static_receiver_guard(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-typerstage-lowercase-static-receiver-guard <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    marker = "(* hxhx(stage3) bootstrap shim: lower-case static receiver guard *)"
    if marker in src:
        write_text(path_str, src)
        return

    old = '''          | HxExpr.EIdent _p0 -> let _g4 = (_p0 : string) in let typeName = (_g4 : string) in let c = Obj.magic (TyperContext.resolveType (Obj.magic ctx) (typeName : string)) in if c != Obj.magic (HxRuntime.hx_null) then ('''
    new = '''          | HxExpr.EIdent _p0 -> let _g4 = (_p0 : string) in let typeName = (_g4 : string) in let c = Obj.magic (if isUpperStartName (typeName : string) then TyperContext.resolveType (Obj.magic ctx) (typeName : string) else Obj.magic (HxRuntime.hx_null)) in if c != Obj.magic (HxRuntime.hx_null) then ('''
    src = replace_one(
        src,
        old,
        new,
        "build-hxhx: failed to locate TyperStage lower-case static receiver guard anchor\n",
    )
    write_text(path_str, src + "\n" + marker + "\n")


def cmd_patch_cli_routing_ocaml_eval_hxml(argv: list[str]) -> None:
    if len(argv) != 1:
        fail("usage: patch-cli-routing-ocaml-eval-hxml <path>\n")
    path_str = argv[0]
    src = read_text(path_str)

    # Newer regenerated bootstrap snapshots already include the planning-aware `--ocaml-eval`
    # argument expansion. Treat those snapshots as converged and skip the legacy anchor patch.
    if (
        "let expandedEvalArgs = Obj.magic (planningTargetArgs (Obj.magic evalArgs))" in src
        and "addLibraryIfMissingForPlanning" in src
        and "addDefineIfMissingForPlanning" in src
    ):
        write_text(path_str, src)
        return

    old = '''        let evalArgs = Obj.magic (HxArray.copy baseForwarded) in let evalReflaxeTarget = (getDefineValue (Obj.magic evalArgs) ("reflaxe-target" : string) : string) in (
          ignore (if evalReflaxeTarget != Obj.magic (HxRuntime.hx_null) && not (HxString.equals evalReflaxeTarget "ocaml") then ignore (HxType.hx_throw_typed_rtti (Obj.repr ("Contradiction: --ocaml-eval but -D reflaxe-target=" ^ HxString.toStdString evalReflaxeTarget)) ["Dynamic"; "String"]) else ());
          ignore (addLibraryIfMissing (Obj.magic evalArgs) ("reflaxe.ocaml" : string));
          ignore (addDefineIfMissing (Obj.magic evalArgs) ("reflaxe-target=ocaml" : string));
          ignore (addDefineIfMissing (Obj.magic evalArgs) ("reflaxe-target-code-injection=ocaml" : string));
          ignore (addDefineIfMissing (Obj.magic evalArgs) ("retain-untyped-meta" : string));
          ignore (addDefineIfMissing (Obj.magic evalArgs) ("ocaml_output=out" : string));
          ignore (addDefineIfMissing (Obj.magic evalArgs) ("ocaml_build=1" : string));
          ignore (addDefineIfMissing (Obj.magic evalArgs) ("ocaml_bin=main" : string));
          ignore (if HxArray.indexOf evalArgs "--no-output" 0 = -1 then ignore (HxArray.push evalArgs "--no-output") else ());
          raise (HxRuntime.Hx_return (Obj.repr (let __anon_3 = HxAnon.create () in (
            ignore (HxAnon.set __anon_3 "lane" (Obj.repr "stage0-ocaml-eval"));
            ignore (HxAnon.set __anon_3 "backendId" (Obj.repr (Obj.magic (HxRuntime.hx_null))));
            ignore (HxAnon.set __anon_3 "forwarded" (Obj.repr evalArgs));
            ignore (HxAnon.set __anon_3 "stage0Required" (HxRuntime.box_bool true));
            __anon_3
          ))))
        )'''

    new = '''        let evalArgs = Obj.magic (HxArray.copy baseForwarded) in let expandedEvalArgs = Obj.magic (planningTargetArgs (Obj.magic evalArgs)) in let evalReflaxeTarget = (getDefineValue (Obj.magic expandedEvalArgs) ("reflaxe-target" : string) : string) in (
          ignore (if evalReflaxeTarget != Obj.magic (HxRuntime.hx_null) && not (HxString.equals evalReflaxeTarget "ocaml") then ignore (HxType.hx_throw_typed_rtti (Obj.repr ("Contradiction: --ocaml-eval but -D reflaxe-target=" ^ HxString.toStdString evalReflaxeTarget)) ["Dynamic"; "String"]) else ());
          ignore (if not (hasLibrary (Obj.magic expandedEvalArgs) ("reflaxe.ocaml" : string)) then ignore (addLibraryIfMissing (Obj.magic evalArgs) ("reflaxe.ocaml" : string)) else ());
          ignore (if not (hasDefine (Obj.magic expandedEvalArgs) ("reflaxe-target" : string)) then ignore (addDefineIfMissing (Obj.magic evalArgs) ("reflaxe-target=ocaml" : string)) else ());
          ignore (if not (hasDefine (Obj.magic expandedEvalArgs) ("reflaxe-target-code-injection" : string)) then ignore (addDefineIfMissing (Obj.magic evalArgs) ("reflaxe-target-code-injection=ocaml" : string)) else ());
          ignore (if not (hasDefine (Obj.magic expandedEvalArgs) ("retain-untyped-meta" : string)) then ignore (addDefineIfMissing (Obj.magic evalArgs) ("retain-untyped-meta" : string)) else ());
          ignore (if not (hasDefine (Obj.magic expandedEvalArgs) ("ocaml_output" : string)) then ignore (addDefineIfMissing (Obj.magic evalArgs) ("ocaml_output=out" : string)) else ());
          ignore (if not (hasDefine (Obj.magic expandedEvalArgs) ("ocaml_build" : string)) then ignore (addDefineIfMissing (Obj.magic evalArgs) ("ocaml_build=1" : string)) else ());
          ignore (if not (hasDefine (Obj.magic expandedEvalArgs) ("ocaml_bin" : string)) then ignore (addDefineIfMissing (Obj.magic evalArgs) ("ocaml_bin=main" : string)) else ());
          ignore (if HxArray.indexOf expandedEvalArgs "--no-output" 0 = -1 && HxArray.indexOf evalArgs "--no-output" 0 = -1 then ignore (HxArray.push evalArgs "--no-output") else ());
          raise (HxRuntime.Hx_return (Obj.repr (let __anon_3 = HxAnon.create () in (
            ignore (HxAnon.set __anon_3 "lane" (Obj.repr "stage0-ocaml-eval"));
            ignore (HxAnon.set __anon_3 "backendId" (Obj.repr (Obj.magic (HxRuntime.hx_null))));
            ignore (HxAnon.set __anon_3 "forwarded" (Obj.repr evalArgs));
            ignore (HxAnon.set __anon_3 "stage0Required" (HxRuntime.box_bool true));
            __anon_3
          ))))
        )'''

    src = replace_one(
        src,
        old,
        new,
        "build-hxhx: failed to locate bootstrap CliRouting --ocaml-eval hxml parity anchor\n",
    )
    write_text(path_str, src)


COMMANDS: Dict[str, Callable[[list[str]], None]] = {
    "insert-before-anchor": cmd_insert_before_anchor,
    "patch-array-receiver-chain-lowering": cmd_patch_array_receiver_chain_lowering,
    "patch-hxparser-interpolated-exprs": cmd_patch_hxparser_interpolated_exprs,
    "patch-hxparser-generic-function-decl": cmd_patch_hxparser_generic_function_decl,
    "patch-hxparser-uppercase-helper-call": cmd_patch_hxparser_uppercase_helper_call,
    "patch-native-parser-generic-arrow-constraints": cmd_patch_native_parser_generic_arrow_constraints,
    "patch-native-parser-expr-spacing": cmd_patch_native_parser_expr_spacing,
    "patch-emitter-typed-param-fallback": cmd_patch_emitter_typed_param_fallback,
    "patch-emitter-parsed-arg-type-overlay": cmd_patch_emitter_parsed_arg_type_overlay,
    "patch-emitter-preapplied-sig-fallback": cmd_patch_emitter_preapplied_sig_fallback,
    "patch-stage1-std-root-termination": cmd_patch_stage1_std_root_termination,
    "patch-allowed-ident-fallback": cmd_patch_allowed_ident_fallback,
    "patch-typed-ty-map-copying": cmd_patch_typed_ty_map_copying,
    "patch-typed-map-helper-obj-repr": cmd_patch_typed_map_helper_obj_repr,
    "patch-fast-emitter-nested-literals": cmd_patch_fast_emitter_nested_literals,
    "patch-nested-emitter-call-arg-reprs": cmd_patch_nested_emitter_call_arg_reprs,
    "patch-extend-ty-ident-call-reprs": cmd_patch_extend_ty_ident_call_reprs,
    "patch-stmt-list-local-hint-reprs": cmd_patch_stmt_list_local_hint_reprs,
    "patch-stmt-list-string-builder": cmd_patch_stmt_list_string_builder,
    "patch-stmt-list-trace": cmd_patch_stmt_list_trace,
    "patch-module-name-lookup-raw-map": cmd_patch_module_name_lookup_raw_map,
    "patch-typed-ty-ident-lookups": cmd_patch_typed_ty_ident_lookups,
    "patch-negative-unop-is-int-expr": cmd_patch_negative_unop_is_int_expr,
    "patch-stmt-local-allowed-idents": cmd_patch_stmt_local_allowed_idents,
    "patch-instance-call-receiver-forwarding": cmd_patch_instance_call_receiver_forwarding,
    "patch-instance-call-this-binding": cmd_patch_instance_call_this_binding,
    "patch-instance-method-value-binding": cmd_patch_instance_method_value_binding,
    "patch-instance-call-preapplied-arity": cmd_patch_instance_call_preapplied_arity,
    "patch-string-length-fallback": cmd_patch_string_length_fallback,
    "patch-string-length-stdlib": cmd_patch_string_length_stdlib,
    "patch-mutable-local-string-init-hints": cmd_patch_mutable_local_string_init_hints,
    "patch-qualified-static-optional-args": cmd_patch_qualified_static_optional_args,
    "patch-preapplied-getstring-optional-arg": cmd_patch_preapplied_getstring_optional_arg,
    "patch-lambda-list-shim": cmd_patch_lambda_list_shim,
    "patch-haxe-ds-list-shim": cmd_patch_haxe_ds_list_shim,
    "patch-string-key-cast-index": cmd_patch_string_key_cast_index,
    "patch-stringtools-hex-optional-digits": cmd_patch_stringtools_hex_optional_digits,
    "patch-mutable-int64-assignment": cmd_patch_mutable_int64_assignment,
    "patch-int64-mixed-binops": cmd_patch_int64_mixed_binops,
    "patch-int64-static-helpers": cmd_patch_int64_static_helpers,
    "patch-float-compare-unknown-numeric": cmd_patch_float_compare_unknown_numeric,
    "patch-int-compare-precedence": cmd_patch_int_compare_precedence,
    "patch-float-modulo-mutable-local": cmd_patch_float_modulo_mutable_local,
    "patch-plugin-dune-layout": cmd_patch_plugin_dune_layout,
    "patch-js-target-core-native-js-lib-externs": cmd_patch_js_target_core_native_js_lib_externs,
    "patch-js-target-core-systools-static-bodies": cmd_patch_js_target_core_systools_static_bodies,
    "patch-hxtype-registry-js-target-core-systools": cmd_patch_hxtype_registry_js_target_core_systools,
    "patch-typerstage-lowercase-static-receiver-guard": cmd_patch_typerstage_lowercase_static_receiver_guard,
    "patch-cli-routing-ocaml-eval-hxml": cmd_patch_cli_routing_ocaml_eval_hxml,
}


def main(argv: list[str]) -> int:
    if not argv:
        fail("usage: bootstrap_patch_helper.py <command> [args...]\n")
    command = argv[0]
    handler = COMMANDS.get(command)
    if handler is None:
        fail(f"unknown command: {command}\n")
    handler(argv[1:])
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
