# Stage3 file-system operations

`Main.hx` creates a scratch directory under `.tmp/`, then writes, reads,
lists, renames, copies, and deletes files and directories with the standard
`sys.io.File` and `sys.FileSystem` APIs. It prints every result, so a call
that does nothing or returns a placeholder shows up as a changed line.

Each operation is spelled both with the imported short name
(`File.getContent(path)`) and with the fully qualified path
(`sys.io.File.getContent(path)`). Before the fix, Stage3 routed only the
short spelling to the OCaml runtime. The qualified spelling called the empty
stub that Stage3 generates for each bodiless method of these `extern`
classes, so the native program printed `0` for a file's content and then
crashed.

`npm run test:m14:stage3-sys-file-ops` checks that upstream Haxe 4.3.7
prints `expected.stdout`. It then builds the program with Stage3 and requires
the native executable to print the same text.
