# [0.8.0](https://github.com/fullofcaffeine/reflaxe.ocaml/compare/v0.7.1...v0.8.0) (2026-01-31)


### Bug Fixes

* **ocaml:** coerce if branches for Null<primitive> ([0a6cad2](https://github.com/fullofcaffeine/reflaxe.ocaml/commit/0a6cad24c986a12cfdedefd7ddb430a5fee4311e))
* **ocaml:** implement early return semantics ([ccf1e71](https://github.com/fullofcaffeine/reflaxe.ocaml/commit/ccf1e716f4131dad3d547c3000df1a0e4f9e6092))
* **ocaml:** implement Null<primitive> semantics ([764d665](https://github.com/fullofcaffeine/reflaxe.ocaml/commit/764d6650f522dd17eec54cb80e859232317a048d))
* **ocaml:** nullable primitive coercions ([984df86](https://github.com/fullofcaffeine/reflaxe.ocaml/commit/984df8678b26089e533299bd55213ce4b92ea779))


### Features

* **ocaml:** support ++/-- semantics ([5357803](https://github.com/fullofcaffeine/reflaxe.ocaml/commit/5357803a2f76e6eb192d45828b74f4ee7db30002))

## [0.7.1](https://github.com/fullofcaffeine/reflaxe.ocaml/compare/v0.7.0...v0.7.1) (2026-01-31)


### Bug Fixes

* **ocaml:** handle enum params and Map types ([436b41f](https://github.com/fullofcaffeine/reflaxe.ocaml/commit/436b41fc6ff2016fd72259f4b34eb1bac46b8f7c))

# [0.7.0](https://github.com/fullofcaffeine/reflaxe.ocaml/compare/v0.6.0...v0.7.0) (2026-01-31)


### Features

* **ocaml:** implement sys.FileSystem.stat and Date runtime ([8b3c811](https://github.com/fullofcaffeine/reflaxe.ocaml/commit/8b3c811004ac1118ae247f3ba8ea21e4f2c87259))

# [0.6.0](https://github.com/fullofcaffeine/reflaxe.ocaml/compare/v0.5.0...v0.6.0) (2026-01-31)


### Features

* **ocaml:** safe null sentinel and portable conformance tests ([0eb4b07](https://github.com/fullofcaffeine/reflaxe.ocaml/commit/0eb4b075907a4e3b559a21ae06f9142de657f208))

# [0.5.0](https://github.com/fullofcaffeine/reflaxe.ocaml/compare/v0.4.0...v0.5.0) (2026-01-30)


### Features

* **ocaml:** align Sys env with Haxe null semantics ([1849821](https://github.com/fullofcaffeine/reflaxe.ocaml/commit/1849821f686f25ae11f0c66853f0f4cb95351e0a))

# [0.4.0](https://github.com/fullofcaffeine/reflaxe.ocaml/compare/v0.3.0...v0.4.0) (2026-01-30)


### Features

* **ocaml:** add Map runtime and iterator support ([bd5dedd](https://github.com/fullofcaffeine/reflaxe.ocaml/commit/bd5deddacdab081ef86f77f960536cda9d53b006))

# [0.3.0](https://github.com/fullofcaffeine/reflaxe.ocaml/compare/v0.2.0...v0.3.0) (2026-01-30)


### Features

* **ocaml:** expand Array support and fix OCaml printing ([fd6d4df](https://github.com/fullofcaffeine/reflaxe.ocaml/commit/fd6d4dff37f0281992e2c6cf1d230ee5dcf4b2a8))

# [0.2.0](https://github.com/fullofcaffeine/reflaxe.ocaml/compare/v0.1.0...v0.2.0) (2026-01-25)


### Bug Fixes

* **ci:** install ocaml-dune on ubuntu-latest ([245ca9f](https://github.com/fullofcaffeine/reflaxe.ocaml/commit/245ca9f3e379a404320cf54e14888e40887cb8fc))
* **ci:** skip CodeQL on private repos by default ([d5cb2c0](https://github.com/fullofcaffeine/reflaxe.ocaml/commit/d5cb2c0a94105770ca1f5ae9707af5a9c33bf050))
* **ocaml:** avoid dune warn-error failures ([0cba70d](https://github.com/fullofcaffeine/reflaxe.ocaml/commit/0cba70d9fd5a472877b6c688e2cf0280aa29c090))
* **ocaml:** improve codegen ordering and typing ([e7bd701](https://github.com/fullofcaffeine/reflaxe.ocaml/commit/e7bd701a6b4bef1b3278cb586ccc00ce03abc617))
* **ocaml:** lower Sys.print/println to OCaml stdio ([ccea6e6](https://github.com/fullofcaffeine/reflaxe.ocaml/commit/ccea6e6867fd68cca254178c6a7cddf48e5bcd31))
* **ocaml:** make dune builds succeed ([5924051](https://github.com/fullofcaffeine/reflaxe.ocaml/commit/59240515d6c09eabbc9bb18aec977f14ba863c1b))


### Features

* **bytes:** add haxe.io.Bytes support ([e5e16bc](https://github.com/fullofcaffeine/reflaxe.ocaml/commit/e5e16bc3b62d6f6634d26ef55581e3446964ce91))
* **examples:** add mini-compiler + QA harness ([788545c](https://github.com/fullofcaffeine/reflaxe.ocaml/commit/788545c62af58184fdd1ac76677d3425b759d5bf))
* **ocaml:** add Sys/File/FileSystem portable runtime ([084eb97](https://github.com/fullofcaffeine/reflaxe.ocaml/commit/084eb97b55f9e2ab7072072cf0423da86769dae2))
* **ocaml:** support break/continue in loops ([5addf49](https://github.com/fullofcaffeine/reflaxe.ocaml/commit/5addf49b82350b67f9d2fc25a820f66143344598))

# Changelog

All notable changes to this project will be documented in this file.

This project uses semantic-release to generate release notes from commit history.
