# file-io

Small acceptance example that exercises:

- `Sys.args()` (no args under CI harness)
- `Sys.getEnv()`
- `sys.FileSystem.createDirectory / exists / readDirectory`
- `sys.io.File.saveContent / getContent / getBytes / saveBytes / copy`

This is intended to QA the runtime shims (`HxSys`, `HxFile`, `HxFileSystem`)
in addition to compiler snapshots.

