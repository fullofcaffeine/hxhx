# Portable Stdlib Parity Matrix (OCaml, Haxe 4.3.7 baseline)

Generated from:
- `docs/00-project/STDLIB_PORTABLE_BASELINE_OCAML_4_3_7.json`
- tracked overrides under `packages/reflaxe.ocaml/std/_std/`

Summary: `204` modules total, `18` overrides, `0` runtime-backed, `186` passthrough/unverified.

| Module | Status | Evidence |
|---|---|---|
| `Any` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `Array` | `override` | packages/reflaxe.ocaml/std/_std/Array.hx |
| `Class` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `Date` | `override` | packages/reflaxe.ocaml/std/_std/Date.hx |
| `DateTools` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `EReg` | `override` | packages/reflaxe.ocaml/std/_std/EReg.hx |
| `Enum` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `EnumValue` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `IntIterator` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `Lambda` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `List` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `Map` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `Math` | `override` | packages/reflaxe.ocaml/std/_std/Math.hx |
| `Reflect` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `Std` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `StdTypes` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `String` | `override` | packages/reflaxe.ocaml/std/_std/String.hx |
| `StringBuf` | `override` | packages/reflaxe.ocaml/std/_std/StringBuf.hx |
| `StringTools` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `Sys` | `override` | packages/reflaxe.ocaml/std/_std/Sys.hx |
| `Type` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `UInt` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `UnicodeString` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `Xml` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.CallStack` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.Constraints` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.DynamicAccess` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.EntryPoint` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.EnumFlags` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.EnumTools` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.Exception` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.Http` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.Int32` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.Int64` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.Int64Helper` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.Json` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.Log` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.MainLoop` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.NativeStackTrace` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.PosInfos` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.Resource` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.Rest` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.Serializer` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.SysTools` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.Template` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.Timer` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.Ucs2` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.Unserializer` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.Utf8` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.ValueException` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.atomic.AtomicBool` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.atomic.AtomicInt` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.atomic.AtomicObject` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.crypto.Adler32` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.crypto.Base64` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.crypto.BaseCode` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.crypto.Crc32` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.crypto.Hmac` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.crypto.Md5` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.crypto.Sha1` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.crypto.Sha224` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.crypto.Sha256` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.display.Diagnostic` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.display.Display` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.display.FsPath` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.display.JsonModuleTypes` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.display.Position` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.display.Protocol` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.display.Server` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.ds.ArraySort` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.ds.BalancedTree` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.ds.Either` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.ds.EnumValueMap` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.ds.GenericStack` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.ds.HashMap` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.ds.IntMap` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.ds.List` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.ds.ListSort` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.ds.Map` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.ds.ObjectMap` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.ds.Option` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.ds.ReadOnlyArray` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.ds.StringMap` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.ds.Vector` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.ds.WeakMap` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.exceptions.ArgumentException` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.exceptions.NotImplementedException` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.exceptions.PosException` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.extern.AsVar` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.extern.EitherType` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.extern.Rest` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.format.JsonParser` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.format.JsonPrinter` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.http.HttpBase` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.http.HttpJs` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.http.HttpMethod` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.http.HttpNodeJs` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.http.HttpStatus` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.io.ArrayBufferView` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.io.BufferInput` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.io.Bytes` | `override` | packages/reflaxe.ocaml/std/_std/haxe/io/Bytes.hx |
| `haxe.io.BytesBuffer` | `override` | packages/reflaxe.ocaml/std/_std/haxe/io/BytesBuffer.hx |
| `haxe.io.BytesData` | `override` | packages/reflaxe.ocaml/std/_std/haxe/io/BytesData.hx |
| `haxe.io.BytesInput` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.io.BytesOutput` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.io.Encoding` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.io.Eof` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.io.Error` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.io.FPHelper` | `override` | packages/reflaxe.ocaml/std/_std/haxe/io/FPHelper.hx |
| `haxe.io.Float32Array` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.io.Float64Array` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.io.Input` | `override` | packages/reflaxe.ocaml/std/_std/haxe/io/Input.hx |
| `haxe.io.Int32Array` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.io.Mime` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.io.Output` | `override` | packages/reflaxe.ocaml/std/_std/haxe/io/Output.hx |
| `haxe.io.Path` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.io.Scheme` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.io.StringInput` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.io.UInt16Array` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.io.UInt32Array` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.io.UInt8Array` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.iterators.ArrayIterator` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.iterators.ArrayKeyValueIterator` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.iterators.DynamicAccessIterator` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.iterators.DynamicAccessKeyValueIterator` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.iterators.HashMapKeyValueIterator` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.iterators.MapKeyValueIterator` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.iterators.RestIterator` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.iterators.RestKeyValueIterator` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.iterators.StringIterator` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.iterators.StringIteratorUnicode` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.iterators.StringKeyValueIterator` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.iterators.StringKeyValueIteratorUnicode` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.macro.CompilationServer` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.macro.Compiler` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.macro.ComplexTypeTools` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.macro.Context` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.macro.DisplayMode` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.macro.ExampleJSGenerator` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.macro.Expr` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.macro.ExprTools` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.macro.Format` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.macro.JSGenApi` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.macro.MacroStringTools` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.macro.MacroType` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.macro.PlatformConfig` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.macro.PositionTools` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.macro.Printer` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.macro.Tools` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.macro.Type` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.macro.TypeTools` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.macro.TypedExprTools` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.rtti.CType` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.rtti.Meta` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.rtti.Rtti` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.rtti.XmlParser` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.xml.Access` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.xml.Check` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.xml.Fast` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.xml.Parser` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.xml.Printer` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.zip.Compress` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.zip.Entry` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.zip.FlushMode` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.zip.Huffman` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.zip.InflateImpl` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.zip.Reader` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.zip.Tools` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.zip.Uncompress` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `haxe.zip.Writer` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.FileStat` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.FileSystem` | `override` | packages/reflaxe.ocaml/std/_std/sys/FileSystem.hx |
| `sys.Http` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.db.Connection` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.db.Mysql` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.db.ResultSet` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.db.Sqlite` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.io.File` | `override` | packages/reflaxe.ocaml/std/_std/sys/io/File.hx |
| `sys.io.FileInput` | `override` | packages/reflaxe.ocaml/std/_std/sys/io/FileInput.hx |
| `sys.io.FileOutput` | `override` | packages/reflaxe.ocaml/std/_std/sys/io/FileOutput.hx |
| `sys.io.FileSeek` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.io.Process` | `override` | packages/reflaxe.ocaml/std/_std/sys/io/Process.hx |
| `sys.net.Address` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.net.Host` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.net.Socket` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.net.UdpSocket` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.ssl.Certificate` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.ssl.Digest` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.ssl.DigestAlgorithm` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.ssl.Key` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.ssl.Socket` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.thread.Condition` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.thread.Deque` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.thread.ElasticThreadPool` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.thread.EventLoop` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.thread.FixedThreadPool` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.thread.IThreadPool` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.thread.Lock` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.thread.Mutex` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.thread.NoEventLoopException` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.thread.Semaphore` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.thread.Thread` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.thread.ThreadPoolException` | `passthrough_or_unverified` | upstream std module, no local override yet |
| `sys.thread.Tls` | `passthrough_or_unverified` | upstream std module, no local override yet |

