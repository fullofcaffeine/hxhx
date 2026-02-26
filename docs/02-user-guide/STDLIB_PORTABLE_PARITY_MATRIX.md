# Portable Stdlib Parity Matrix (OCaml, Haxe 4.3.7 baseline)

Generated from:
- `docs/00-project/STDLIB_PORTABLE_BASELINE_OCAML_4_3_7.json`
- `docs/00-project/STDLIB_PORTABLE_EVIDENCE_OCAML_4_3_7.json`
- tracked overrides under `packages/reflaxe.ocaml/std/_std/`

Summary: `204` modules total, `24` overrides, `2` runtime-backed, `5` lowering-intrinsic, `137` passthrough-verified, `36` passthrough-unverified.

| Module | Status | Evidence |
|---|---|---|
| `Any` | `passthrough_verified` | test/portable/fixtures/stdlib_core_01/src/Main.hx |
| `Array` | `override` | packages/reflaxe.ocaml/std/_std/Array.hx |
| `Class` | `passthrough_verified` | test/portable/fixtures/stdlib_core_01/src/Main.hx |
| `Date` | `override` | packages/reflaxe.ocaml/std/_std/Date.hx |
| `DateTools` | `passthrough_verified` | test/portable/fixtures/stdlib_core_01/src/Main.hx |
| `EReg` | `override` | packages/reflaxe.ocaml/std/_std/EReg.hx |
| `Enum` | `passthrough_verified` | test/portable/fixtures/stdlib_core_01/src/Main.hx |
| `EnumValue` | `passthrough_verified` | test/portable/fixtures/stdlib_core_01/src/Main.hx |
| `IntIterator` | `passthrough_verified` | test/portable/fixtures/stdlib_core_01/src/Main.hx |
| `Lambda` | `passthrough_verified` | test/portable/fixtures/stdlib_core_01/src/Main.hx |
| `List` | `passthrough_verified` | test/portable/fixtures/stdlib_core_01/src/Main.hx |
| `Map` | `lowering_intrinsic` | packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlBuilder.hx |
| `Math` | `override` | packages/reflaxe.ocaml/std/_std/Math.hx |
| `Reflect` | `passthrough_verified` | test/portable/fixtures/reflect_call_method_basic/src/Main.hx; test/portable/fixtures/reflect_dynamic_fields/src/Main.hx |
| `Std` | `passthrough_verified` | test/portable/fixtures/stdlib_core_01/src/Main.hx |
| `StdTypes` | `passthrough_verified` | test/portable/fixtures/stdlib_core_01/src/Main.hx |
| `String` | `override` | packages/reflaxe.ocaml/std/_std/String.hx |
| `StringBuf` | `override` | packages/reflaxe.ocaml/std/_std/StringBuf.hx |
| `StringTools` | `passthrough_verified` | test/portable/fixtures/stdlib_core_01/src/Main.hx |
| `Sys` | `override` | packages/reflaxe.ocaml/std/_std/Sys.hx |
| `Type` | `passthrough_verified` | test/portable/fixtures/type_getclass_basic/src/Main.hx; test/portable/fixtures/type_reflection_basic/src/Main.hx |
| `UInt` | `passthrough_verified` | test/portable/fixtures/stdlib_core_01/src/Main.hx |
| `UnicodeString` | `passthrough_verified` | test/portable/fixtures/stdlib_core_01/src/Main.hx |
| `Xml` | `override` | packages/reflaxe.ocaml/std/_std/Xml.hx; test/portable/fixtures/xml_basic/src/Main.hx; test/portable/fixtures/xml_parse_basic/src/Main.hx |
| `haxe.CallStack` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket01_basic/src/Main.hx |
| `haxe.Constraints` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket01_basic/src/Main.hx |
| `haxe.DynamicAccess` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket01_basic/src/Main.hx |
| `haxe.EntryPoint` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket01_basic/src/Main.hx |
| `haxe.EnumFlags` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket01_basic/src/Main.hx |
| `haxe.EnumTools` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket01_basic/src/Main.hx |
| `haxe.Exception` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket01_basic/src/Main.hx |
| `haxe.Http` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket01_basic/src/Main.hx |
| `haxe.Int32` | `passthrough_verified` | test/portable/fixtures/int32_semantics/src/Main.hx |
| `haxe.Int64` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket01_basic/src/Main.hx |
| `haxe.Int64Helper` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket01_basic/src/Main.hx |
| `haxe.Json` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket01_basic/src/Main.hx |
| `haxe.Log` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket01_basic/src/Main.hx |
| `haxe.MainLoop` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket02_basic/src/Main.hx |
| `haxe.NativeStackTrace` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket02_basic/src/Main.hx |
| `haxe.PosInfos` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket02_basic/src/Main.hx |
| `haxe.Resource` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket02_basic/src/Main.hx |
| `haxe.Rest` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket02_basic/src/Main.hx |
| `haxe.Serializer` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket02_basic/src/Main.hx |
| `haxe.SysTools` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket02_basic/src/Main.hx |
| `haxe.Template` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket02_basic/src/Main.hx |
| `haxe.Timer` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket02_basic/src/Main.hx |
| `haxe.Ucs2` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket02_basic/src/Main.hx |
| `haxe.Unserializer` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket02_basic/src/Main.hx |
| `haxe.Utf8` | `passthrough_verified` | test/portable/fixtures/haxe_core_bucket02_basic/src/Main.hx |
| `haxe.ValueException` | `passthrough_verified` | test/portable/fixtures/haxe_value_exception_basic/src/Main.hx |
| `haxe.atomic.AtomicBool` | `override` | packages/reflaxe.ocaml/std/_std/haxe/atomic/AtomicBool.hx; test/portable/fixtures/haxe_atomic_basic/src/Main.hx |
| `haxe.atomic.AtomicInt` | `override` | packages/reflaxe.ocaml/std/_std/haxe/atomic/AtomicInt.hx; test/portable/fixtures/haxe_atomic_basic/src/Main.hx |
| `haxe.atomic.AtomicObject` | `override` | packages/reflaxe.ocaml/std/_std/haxe/atomic/AtomicObject.hx; test/portable/fixtures/haxe_atomic_basic/src/Main.hx |
| `haxe.crypto.Adler32` | `passthrough_verified` | test/portable/fixtures/haxe_crypto_bucket01_basic/src/Main.hx |
| `haxe.crypto.Base64` | `passthrough_verified` | test/portable/fixtures/haxe_crypto_bucket01_basic/src/Main.hx |
| `haxe.crypto.BaseCode` | `passthrough_verified` | test/portable/fixtures/haxe_crypto_bucket01_basic/src/Main.hx |
| `haxe.crypto.Crc32` | `passthrough_verified` | test/portable/fixtures/haxe_crypto_bucket01_basic/src/Main.hx |
| `haxe.crypto.Hmac` | `passthrough_verified` | test/portable/fixtures/haxe_crypto_hmac_basic/src/Main.hx |
| `haxe.crypto.Md5` | `passthrough_verified` | test/portable/fixtures/haxe_crypto_bucket01_basic/src/Main.hx |
| `haxe.crypto.Sha1` | `passthrough_verified` | test/portable/fixtures/haxe_crypto_bucket01_basic/src/Main.hx |
| `haxe.crypto.Sha224` | `passthrough_verified` | test/portable/fixtures/haxe_crypto_bucket01_basic/src/Main.hx |
| `haxe.crypto.Sha256` | `passthrough_verified` | test/portable/fixtures/haxe_crypto_bucket01_basic/src/Main.hx |
| `haxe.display.Diagnostic` | `passthrough_verified` | test/portable/fixtures/haxe_display_bucket01_basic/src/Main.hx |
| `haxe.display.Display` | `passthrough_verified` | test/portable/fixtures/haxe_display_bucket01_basic/src/Main.hx |
| `haxe.display.FsPath` | `passthrough_verified` | test/portable/fixtures/haxe_display_bucket01_basic/src/Main.hx |
| `haxe.display.JsonModuleTypes` | `passthrough_verified` | test/portable/fixtures/haxe_display_bucket01_basic/src/Main.hx |
| `haxe.display.Position` | `passthrough_verified` | test/portable/fixtures/haxe_display_bucket01_basic/src/Main.hx |
| `haxe.display.Protocol` | `passthrough_verified` | test/portable/fixtures/haxe_display_bucket01_basic/src/Main.hx |
| `haxe.display.Server` | `passthrough_verified` | test/portable/fixtures/haxe_display_bucket01_basic/src/Main.hx |
| `haxe.ds.ArraySort` | `passthrough_verified` | test/portable/fixtures/haxe_ds_bucket01_basic/src/Main.hx |
| `haxe.ds.BalancedTree` | `passthrough_verified` | test/portable/fixtures/haxe_ds_bucket01_basic/src/Main.hx |
| `haxe.ds.Either` | `passthrough_verified` | test/portable/fixtures/haxe_ds_bucket01_basic/src/Main.hx |
| `haxe.ds.EnumValueMap` | `passthrough_verified` | test/portable/fixtures/haxe_ds_bucket01_basic/src/Main.hx |
| `haxe.ds.GenericStack` | `passthrough_verified` | test/portable/fixtures/haxe_ds_bucket01_basic/src/Main.hx |
| `haxe.ds.HashMap` | `passthrough_verified` | test/portable/fixtures/haxe_ds_bucket01_basic/src/Main.hx |
| `haxe.ds.IntMap` | `lowering_intrinsic` | packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlBuilder.hx |
| `haxe.ds.List` | `passthrough_verified` | test/portable/fixtures/haxe_ds_bucket01_basic/src/Main.hx |
| `haxe.ds.ListSort` | `passthrough_verified` | test/portable/fixtures/haxe_ds_bucket01_basic/src/Main.hx |
| `haxe.ds.Map` | `lowering_intrinsic` | packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlBuilder.hx |
| `haxe.ds.ObjectMap` | `lowering_intrinsic` | packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlBuilder.hx |
| `haxe.ds.Option` | `passthrough_verified` | test/portable/fixtures/haxe_ds_bucket01_basic/src/Main.hx |
| `haxe.ds.ReadOnlyArray` | `passthrough_verified` | test/portable/fixtures/haxe_ds_bucket01_basic/src/Main.hx |
| `haxe.ds.StringMap` | `lowering_intrinsic` | packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlBuilder.hx |
| `haxe.ds.Vector` | `passthrough_verified` | test/portable/fixtures/haxe_ds_bucket01_basic/src/Main.hx |
| `haxe.ds.WeakMap` | `passthrough_verified` | test/portable/fixtures/haxe_ds_bucket01_basic/src/Main.hx |
| `haxe.exceptions.ArgumentException` | `passthrough_verified` | test/portable/fixtures/haxe_exceptions_basic/src/Main.hx |
| `haxe.exceptions.NotImplementedException` | `passthrough_verified` | test/portable/fixtures/haxe_exceptions_basic/src/Main.hx |
| `haxe.exceptions.PosException` | `passthrough_verified` | test/portable/fixtures/haxe_exceptions_basic/src/Main.hx |
| `haxe.extern.AsVar` | `passthrough_verified` | test/portable/fixtures/haxe_extern_core_basic/src/Main.hx |
| `haxe.extern.EitherType` | `passthrough_verified` | test/portable/fixtures/haxe_extern_core_basic/src/Main.hx |
| `haxe.extern.Rest` | `passthrough_verified` | test/portable/fixtures/haxe_extern_core_basic/src/Main.hx |
| `haxe.format.JsonParser` | `override` | packages/reflaxe.ocaml/std/_std/haxe/format/JsonParser.hx; test/portable/fixtures/haxe_format_json_basic/src/Main.hx |
| `haxe.format.JsonPrinter` | `override` | packages/reflaxe.ocaml/std/_std/haxe/format/JsonPrinter.hx; test/portable/fixtures/haxe_format_json_basic/src/Main.hx |
| `haxe.http.HttpBase` | `passthrough_verified` | test/portable/fixtures/haxe_http_bucket01_basic/src/Main.hx |
| `haxe.http.HttpJs` | `passthrough_verified` | test/portable/fixtures/haxe_http_bucket01_basic/src/Main.hx |
| `haxe.http.HttpMethod` | `passthrough_verified` | test/portable/fixtures/haxe_http_bucket01_basic/src/Main.hx |
| `haxe.http.HttpNodeJs` | `passthrough_verified` | test/portable/fixtures/haxe_http_bucket01_basic/src/Main.hx |
| `haxe.http.HttpStatus` | `passthrough_verified` | test/portable/fixtures/haxe_http_bucket01_basic/src/Main.hx |
| `haxe.io.ArrayBufferView` | `passthrough_verified` | test/portable/fixtures/haxe_io_bucket01_basic/src/Main.hx |
| `haxe.io.BufferInput` | `passthrough_verified` | test/portable/fixtures/haxe_io_bucket01_basic/src/Main.hx |
| `haxe.io.Bytes` | `override` | packages/reflaxe.ocaml/std/_std/haxe/io/Bytes.hx |
| `haxe.io.BytesBuffer` | `override` | packages/reflaxe.ocaml/std/_std/haxe/io/BytesBuffer.hx |
| `haxe.io.BytesData` | `override` | packages/reflaxe.ocaml/std/_std/haxe/io/BytesData.hx |
| `haxe.io.BytesInput` | `passthrough_verified` | test/portable/fixtures/haxe_io_bucket01_basic/src/Main.hx |
| `haxe.io.BytesOutput` | `passthrough_verified` | test/portable/fixtures/haxe_io_bucket01_basic/src/Main.hx |
| `haxe.io.Encoding` | `passthrough_verified` | test/portable/fixtures/haxe_io_bucket01_basic/src/Main.hx |
| `haxe.io.Eof` | `runtime_backed` | packages/reflaxe.ocaml/std/runtime/HxInput.ml |
| `haxe.io.Error` | `runtime_backed` | packages/reflaxe.ocaml/std/runtime/HxInput.ml |
| `haxe.io.FPHelper` | `override` | packages/reflaxe.ocaml/std/_std/haxe/io/FPHelper.hx |
| `haxe.io.Float32Array` | `passthrough_verified` | test/portable/fixtures/haxe_io_bucket01_basic/src/Main.hx |
| `haxe.io.Float64Array` | `passthrough_verified` | test/portable/fixtures/haxe_io_bucket01_basic/src/Main.hx |
| `haxe.io.Input` | `override` | packages/reflaxe.ocaml/std/_std/haxe/io/Input.hx |
| `haxe.io.Int32Array` | `passthrough_verified` | test/portable/fixtures/haxe_io_bucket01_basic/src/Main.hx |
| `haxe.io.Mime` | `passthrough_verified` | test/portable/fixtures/haxe_io_bucket01_basic/src/Main.hx |
| `haxe.io.Output` | `override` | packages/reflaxe.ocaml/std/_std/haxe/io/Output.hx |
| `haxe.io.Path` | `passthrough_verified` | test/portable/fixtures/path_basic/src/Main.hx |
| `haxe.io.Scheme` | `passthrough_verified` | test/portable/fixtures/haxe_io_bucket01_basic/src/Main.hx |
| `haxe.io.StringInput` | `passthrough_verified` | test/portable/fixtures/haxe_io_bucket01_basic/src/Main.hx |
| `haxe.io.UInt16Array` | `passthrough_verified` | test/portable/fixtures/haxe_io_bucket01_basic/src/Main.hx |
| `haxe.io.UInt32Array` | `passthrough_verified` | test/portable/fixtures/haxe_io_bucket02_basic/src/Main.hx |
| `haxe.io.UInt8Array` | `passthrough_verified` | test/portable/fixtures/haxe_io_bucket02_basic/src/Main.hx |
| `haxe.iterators.ArrayIterator` | `passthrough_verified` | test/portable/fixtures/haxe_iterators_bucket01_basic/src/Main.hx |
| `haxe.iterators.ArrayKeyValueIterator` | `passthrough_verified` | test/portable/fixtures/haxe_iterators_bucket01_basic/src/Main.hx |
| `haxe.iterators.DynamicAccessIterator` | `passthrough_verified` | test/portable/fixtures/haxe_iterators_bucket01_basic/src/Main.hx |
| `haxe.iterators.DynamicAccessKeyValueIterator` | `passthrough_verified` | test/portable/fixtures/haxe_iterators_bucket01_basic/src/Main.hx |
| `haxe.iterators.HashMapKeyValueIterator` | `passthrough_verified` | test/portable/fixtures/haxe_iterators_bucket01_basic/src/Main.hx |
| `haxe.iterators.MapKeyValueIterator` | `passthrough_verified` | test/portable/fixtures/haxe_iterators_bucket01_basic/src/Main.hx |
| `haxe.iterators.RestIterator` | `passthrough_verified` | test/portable/fixtures/haxe_iterators_bucket01_basic/src/Main.hx |
| `haxe.iterators.RestKeyValueIterator` | `passthrough_verified` | test/portable/fixtures/haxe_iterators_bucket01_basic/src/Main.hx |
| `haxe.iterators.StringIterator` | `passthrough_verified` | test/portable/fixtures/haxe_iterators_bucket01_basic/src/Main.hx |
| `haxe.iterators.StringIteratorUnicode` | `passthrough_verified` | test/portable/fixtures/haxe_iterators_bucket01_basic/src/Main.hx |
| `haxe.iterators.StringKeyValueIterator` | `passthrough_verified` | test/portable/fixtures/haxe_iterators_bucket01_basic/src/Main.hx |
| `haxe.iterators.StringKeyValueIteratorUnicode` | `passthrough_verified` | test/portable/fixtures/haxe_iterators_bucket01_basic/src/Main.hx |
| `haxe.macro.CompilationServer` | `passthrough_verified` | test/portable/fixtures/haxe_macro_bucket01_basic/src/Main.hx |
| `haxe.macro.Compiler` | `passthrough_verified` | test/portable/fixtures/haxe_macro_bucket01_basic/src/Main.hx |
| `haxe.macro.ComplexTypeTools` | `passthrough_verified` | test/portable/fixtures/haxe_macro_bucket01_basic/src/Main.hx |
| `haxe.macro.Context` | `passthrough_verified` | test/portable/fixtures/haxe_macro_bucket01_basic/src/Main.hx |
| `haxe.macro.DisplayMode` | `passthrough_verified` | test/portable/fixtures/haxe_macro_bucket01_basic/src/Main.hx |
| `haxe.macro.ExampleJSGenerator` | `passthrough_verified` | test/portable/fixtures/haxe_macro_bucket01_basic/src/Main.hx |
| `haxe.macro.Expr` | `passthrough_verified` | test/portable/fixtures/haxe_macro_bucket01_basic/src/Main.hx |
| `haxe.macro.ExprTools` | `passthrough_verified` | test/portable/fixtures/haxe_macro_bucket01_basic/src/Main.hx |
| `haxe.macro.Format` | `passthrough_verified` | test/portable/fixtures/haxe_macro_bucket01_basic/src/Main.hx |
| `haxe.macro.JSGenApi` | `passthrough_verified` | test/portable/fixtures/haxe_macro_bucket01_basic/src/Main.hx |
| `haxe.macro.MacroStringTools` | `passthrough_verified` | test/portable/fixtures/haxe_macro_bucket01_basic/src/Main.hx |
| `haxe.macro.MacroType` | `passthrough_verified` | test/portable/fixtures/haxe_macro_bucket01_basic/src/Main.hx |
| `haxe.macro.PlatformConfig` | `passthrough_verified` | test/portable/fixtures/haxe_macro_bucket02_basic/src/Main.hx |
| `haxe.macro.PositionTools` | `passthrough_verified` | test/portable/fixtures/haxe_macro_bucket02_basic/src/Main.hx |
| `haxe.macro.Printer` | `passthrough_verified` | test/portable/fixtures/haxe_macro_bucket02_basic/src/Main.hx |
| `haxe.macro.Tools` | `passthrough_verified` | test/portable/fixtures/haxe_macro_bucket02_basic/src/Main.hx |
| `haxe.macro.Type` | `passthrough_verified` | test/portable/fixtures/haxe_macro_bucket02_basic/src/Main.hx |
| `haxe.macro.TypeTools` | `passthrough_verified` | test/portable/fixtures/haxe_macro_bucket02_basic/src/Main.hx |
| `haxe.macro.TypedExprTools` | `passthrough_verified` | test/portable/fixtures/haxe_macro_bucket02_basic/src/Main.hx |
| `haxe.rtti.CType` | `passthrough_verified` | test/portable/fixtures/haxe_rtti_bucket01_basic/src/Main.hx |
| `haxe.rtti.Meta` | `passthrough_verified` | test/portable/fixtures/haxe_rtti_bucket01_basic/src/Main.hx |
| `haxe.rtti.Rtti` | `passthrough_verified` | test/portable/fixtures/haxe_rtti_bucket01_basic/src/Main.hx |
| `haxe.rtti.XmlParser` | `passthrough_verified` | test/portable/fixtures/haxe_rtti_bucket01_basic/src/Main.hx |
| `haxe.xml.Access` | `passthrough_verified` | test/portable/fixtures/haxe_xml_bucket01_basic/src/Main.hx |
| `haxe.xml.Check` | `passthrough_verified` | test/portable/fixtures/haxe_xml_bucket01_basic/src/Main.hx |
| `haxe.xml.Fast` | `passthrough_verified` | test/portable/fixtures/haxe_xml_bucket01_basic/src/Main.hx |
| `haxe.xml.Parser` | `passthrough_verified` | test/portable/fixtures/haxe_xml_bucket01_basic/src/Main.hx |
| `haxe.xml.Printer` | `passthrough_verified` | test/portable/fixtures/haxe_xml_bucket01_basic/src/Main.hx |
| `haxe.zip.Compress` | `passthrough_verified` | test/portable/fixtures/haxe_zip_bucket01_basic/src/Main.hx |
| `haxe.zip.Entry` | `passthrough_verified` | test/portable/fixtures/haxe_zip_bucket01_basic/src/Main.hx |
| `haxe.zip.FlushMode` | `passthrough_verified` | test/portable/fixtures/haxe_zip_bucket01_basic/src/Main.hx |
| `haxe.zip.Huffman` | `passthrough_verified` | test/portable/fixtures/haxe_zip_bucket01_basic/src/Main.hx |
| `haxe.zip.InflateImpl` | `passthrough_verified` | test/portable/fixtures/haxe_zip_bucket01_basic/src/Main.hx |
| `haxe.zip.Reader` | `passthrough_verified` | test/portable/fixtures/haxe_zip_bucket01_basic/src/Main.hx |
| `haxe.zip.Tools` | `passthrough_verified` | test/portable/fixtures/haxe_zip_bucket01_basic/src/Main.hx |
| `haxe.zip.Uncompress` | `passthrough_verified` | test/portable/fixtures/haxe_zip_bucket01_basic/src/Main.hx |
| `haxe.zip.Writer` | `passthrough_verified` | test/portable/fixtures/haxe_zip_bucket01_basic/src/Main.hx |
| `sys.FileStat` | `passthrough_verified` | test/portable/fixtures/file_stat_basic/src/Main.hx |
| `sys.FileSystem` | `override` | packages/reflaxe.ocaml/std/_std/sys/FileSystem.hx |
| `sys.Http` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.db.Connection` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.db.Mysql` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.db.ResultSet` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.db.Sqlite` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.io.File` | `override` | packages/reflaxe.ocaml/std/_std/sys/io/File.hx |
| `sys.io.FileInput` | `override` | packages/reflaxe.ocaml/std/_std/sys/io/FileInput.hx |
| `sys.io.FileOutput` | `override` | packages/reflaxe.ocaml/std/_std/sys/io/FileOutput.hx |
| `sys.io.FileSeek` | `passthrough_verified` | test/portable/fixtures/sys_file_seek_basic/src/Main.hx |
| `sys.io.Process` | `override` | packages/reflaxe.ocaml/std/_std/sys/io/Process.hx |
| `sys.net.Address` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.net.Host` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.net.Socket` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.net.UdpSocket` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.ssl.Certificate` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.ssl.Digest` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.ssl.DigestAlgorithm` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.ssl.Key` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.ssl.Socket` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.thread.Condition` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.thread.Deque` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.thread.ElasticThreadPool` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.thread.EventLoop` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.thread.FixedThreadPool` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.thread.IThreadPool` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.thread.Lock` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.thread.Mutex` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.thread.NoEventLoopException` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.thread.Semaphore` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.thread.Thread` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.thread.ThreadPoolException` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
| `sys.thread.Tls` | `passthrough_unverified` | upstream std module, no explicit portable evidence yet |
