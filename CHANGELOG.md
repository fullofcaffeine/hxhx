## [0.9.6](https://github.com/fullofcaffeine/hxhx/compare/v0.9.5...v0.9.6) (2026-02-20)


### Bug Fixes

* **js-native:** fail fast on class constructor lowering ([44b72e4](https://github.com/fullofcaffeine/hxhx/commit/44b72e4984c7bac6561fa7e40d96fffa418aa347))

## [0.9.5](https://github.com/fullofcaffeine/hxhx/compare/v0.9.4...v0.9.5) (2026-02-20)


### Bug Fixes

* **stage0:** normalize nullable SIf branch rewriting ([343ff63](https://github.com/fullofcaffeine/hxhx/commit/343ff6390b86fcf037832596f089a5e8cbfae3d2))

## [0.9.4](https://github.com/fullofcaffeine/hxhx/compare/v0.9.3...v0.9.4) (2026-02-20)


### Bug Fixes

* **stage0:** normalize nullable HxExpr rewrite paths ([32157c8](https://github.com/fullofcaffeine/hxhx/commit/32157c8cca555b0fb6a817ac40636cf5581c2bc9))

## [0.9.3](https://github.com/fullofcaffeine/hxhx/compare/v0.9.2...v0.9.3) (2026-02-20)


### Bug Fixes

* **stage0:** avoid if-expression nullable HxStmt coercion ([2c8f4f5](https://github.com/fullofcaffeine/hxhx/commit/2c8f4f5a5fb9981afd2759c54092fbd5abb2aa6d))

## [0.9.2](https://github.com/fullofcaffeine/hxhx/compare/v0.9.1...v0.9.2) (2026-02-20)


### Bug Fixes

* **stage0:** stabilize nullable HxStmt branch lowering ([c3af270](https://github.com/fullofcaffeine/hxhx/commit/c3af2702998938fb578de51c5692eb1bd692ec2e))

## [0.9.1](https://github.com/fullofcaffeine/hxhx/compare/v0.9.0...v0.9.1) (2026-02-20)


### Bug Fixes

* **stage0:** allow native-to-byte fallback on build failures ([0715756](https://github.com/fullofcaffeine/hxhx/commit/071575615ce758550ac5795f49a49c36cc4d72f2))

# [0.9.0](https://github.com/fullofcaffeine/hxhx/compare/v0.8.0...v0.9.0) (2026-02-19)


### Bug Fixes

* **builder:** avoid unused let bindings ([b1de774](https://github.com/fullofcaffeine/hxhx/commit/b1de7741f0d9e9439c73168750cf33a780a08172))
* **ci:** refresh bootstrap snapshot and repair stage3 backend dispatch ([0d3ea8b](https://github.com/fullofcaffeine/hxhx/commit/0d3ea8b20beee99bfee7a1f2fa6e14a3b63baf84))
* **codegen:** float operators and division semantics ([76817c9](https://github.com/fullofcaffeine/hxhx/commit/76817c9fb9090c1bf7e066f47aab6a5fef46b18f))
* **codegen:** handle nullable primitive coercions ([ab2ffcf](https://github.com/fullofcaffeine/hxhx/commit/ab2ffcfac7ae802befaa5fedff75f6e828e17a8b))
* **codegen:** nullable primitive switch case null ([ace20be](https://github.com/fullofcaffeine/hxhx/commit/ace20be24c569af7e7d5dafa7ef66328854a237e))
* exception semantics + portable conformance ([47a6073](https://github.com/fullofcaffeine/hxhx/commit/47a607337de7d3e7ea85b6c402c5829196fcc58e))
* **format:** stabilize OcamlBuilder deterministic formatting ([b459389](https://github.com/fullofcaffeine/hxhx/commit/b4593898f190350444b7b29dd60daf4c18788b5a))
* **gate1:** make darwin segfault handling deterministic ([aa5801f](https://github.com/fullofcaffeine/hxhx/commit/aa5801f4520555c7e857ddcc148af317a54507cd))
* **gate1:** remove darwin skip and harden native unit-macro rungs ([83a708a](https://github.com/fullofcaffeine/hxhx/commit/83a708a64923a5a7345f3690353827edfc53a743))
* **gate2:** stage3 emit-runner sys env + exact-case resolve ([115bef5](https://github.com/fullofcaffeine/hxhx/commit/115bef50918a7afdb297ec9197fd424682852562))
* harden EReg.matchSub optional len in stage3 gates ([7034a77](https://github.com/fullofcaffeine/hxhx/commit/7034a776e2f172202faa4f924b62372e87fa1569))
* **hxhx:** clean Stage3 emit OCaml warnings ([53acfb8](https://github.com/fullofcaffeine/hxhx/commit/53acfb813a04b9b02eb859fb3a7df0d89ab36673))
* **hxhx:** discover module-local typedef/abstract declarations ([a4ebb4d](https://github.com/fullofcaffeine/hxhx/commit/a4ebb4d3c10a02b1fcaa10afc426fe55e56ed2f2))
* **hxhx:** gate2 stage3 emit-runner switch semantics ([ebbfe6f](https://github.com/fullofcaffeine/hxhx/commit/ebbfe6ff8b5e51bf5632528c42b6deea5962986b))
* **hxhx:** handle root-package lazy module loading ([7ab6525](https://github.com/fullofcaffeine/hxhx/commit/7ab6525ffa6b460d3820e0b1570229f79e88181a))
* **hxhx:** harden stage3 emit rung ([c5ad21e](https://github.com/fullofcaffeine/hxhx/commit/c5ad21ef246a089a117b6529bdfe93d370cf1c53))
* **hxhx:** harden stage3 receiver forwarding + stage0 log paths ([2a03511](https://github.com/fullofcaffeine/hxhx/commit/2a0351197f6fc96737ac770923d981db6d00979f))
* **hxhx:** harden Stage4 macro host overrides ([9fbe6c2](https://github.com/fullofcaffeine/hxhx/commit/9fbe6c294361a3a50781a71da4e4a7a2aa523626))
* **hxhx:** honor --each common prefix in .hxml ([a3b41b7](https://github.com/fullofcaffeine/hxhx/commit/a3b41b71dfdb9f10448b25793f607a2da25b06c7))
* **hxhx:** improve stage3 emitter string concat ([49d1877](https://github.com/fullofcaffeine/hxhx/commit/49d1877c43a1b90b8f96f24580fe7043b943d4f4))
* **hxhx:** keep typedef/abstract helpers in forced pure parser ([aee6503](https://github.com/fullofcaffeine/hxhx/commit/aee6503d0e662acc9f5719cdcc5caa55ae3bd9b4))
* **hxhx:** native parser selects expected class ([c856d2f](https://github.com/fullofcaffeine/hxhx/commit/c856d2f493c39c1f6441bb2b89f01f8d2575d332))
* **hxhx:** stage3 sys.FileSystem/Path rewrites ([2b0fd46](https://github.com/fullofcaffeine/hxhx/commit/2b0fd460a037e1a8ab082bc48541da4f3bcee09e))
* **hxhx:** unblock gate1 stage3 xml and float unary regressions ([7ec89c2](https://github.com/fullofcaffeine/hxhx/commit/7ec89c2ffa8f88ce228f6af1c36312c6d62710db))
* **hxhx:** unblock Gate2 Stage3 emitter (vars, new<T>(), Int64) ([3012713](https://github.com/fullofcaffeine/hxhx/commit/30127130c1621d90ebc07b5b521c51af519026c3))
* **hxhx:** unblock stage3 runner process lifecycle ([099c6b8](https://github.com/fullofcaffeine/hxhx/commit/099c6b8a2763819877c7c29e68d1a1115bea3e96))
* **interop:** optional labelled args via @:ocamlLabel ([0d74b94](https://github.com/fullofcaffeine/hxhx/commit/0d74b94e20fc544e2592d9fc5e000f0eddab45ef))
* **m10:** Dynamic/Any == semantics ([f01a6bf](https://github.com/fullofcaffeine/hxhx/commit/f01a6bf4fb7b72ecce3c841fcd221bd3d49d1ad0))
* **m10:** switch statement type unification ([6423412](https://github.com/fullofcaffeine/hxhx/commit/6423412e87b9aa824e4d739e4a06a3d985ed5071))
* **m7:** make full strict bundle host-aware for gate3 ([ca0408b](https://github.com/fullofcaffeine/hxhx/commit/ca0408b6a395bbbd59573ca36c9237b882a1780f))
* **ocaml:** disambiguate nested match in switch ([2321917](https://github.com/fullofcaffeine/hxhx/commit/2321917b566ca4b38090186a5f8a3fb18685edde))
* optional args for function values ([d62ccd6](https://github.com/fullofcaffeine/hxhx/commit/d62ccd60da480b02fc65e11d2d6ef29ca499d164))
* restore hxhx macro host + FPHelper ([7051389](https://github.com/fullofcaffeine/hxhx/commit/70513891eed3e61f146aea9d2919747761d9c3b0))
* **runtime:** implement Std extern ([89a4995](https://github.com/fullofcaffeine/hxhx/commit/89a4995c87a149ffb6081c88870f0046123f0ca3))
* **stage3:** dedupe ml units before ocamlopt ([deab4e8](https://github.com/fullofcaffeine/hxhx/commit/deab4e828f78a22de6a6ab637df14c91007efdf0))
* **stage3:** emit module-local helper types (Gate1) ([de9b148](https://github.com/fullofcaffeine/hxhx/commit/de9b14840e9dc6202bc6f7a60d9c1a4a9f080893))
* **stage3:** expand lazy deps and harden full emit ([c1527ce](https://github.com/fullofcaffeine/hxhx/commit/c1527cebf9d3a0ace17c90f130e745ff4b06c324))
* **stage3:** fail fast on missing macro api in display emit-run ([19d2b69](https://github.com/fullofcaffeine/hxhx/commit/19d2b69878276bd0e2aeac9ad9cce5e230bcf416))
* **stage3:** interpolation works in non-print contexts ([72d6dfe](https://github.com/fullofcaffeine/hxhx/commit/72d6dfea04a8b33dee9fb7e1e037871172f068de))
* **stage3:** keep parsing after stray } ([4f7d1c0](https://github.com/fullofcaffeine/hxhx/commit/4f7d1c006080a2371bea83e0277368be278dee44))
* **stage3:** pad receiver-aware qualified calls in widened emit ([57dfb82](https://github.com/fullofcaffeine/hxhx/commit/57dfb8284e93aa396c7c55d76b050c6d75eef9ab))
* **stage3:** stabilize display warm-out full-emit and add stress gate ([959ce7c](https://github.com/fullofcaffeine/hxhx/commit/959ce7c4c48972d71d957de72f73a0c4a92f835e))
* **std:** allow IO subclasses without super ([630eb85](https://github.com/fullofcaffeine/hxhx/commit/630eb85857ac96c894399f0c9f1aa1ab6d0a1dc1))
* unblock hxhx build + stdlib bytes/int64 ([0f81117](https://github.com/fullofcaffeine/hxhx/commit/0f811176f5396f4cf1a0416ea1fd4244b80319a6))


### Features

* **bench:** add M14 benchmark harness ([2f9ad0b](https://github.com/fullofcaffeine/hxhx/commit/2f9ad0b8d11e3d5feb9c24f71eeb209eab182c7e))
* **display:** synthesize ExprOf<T> structure completion in stage3 ([af2a6d9](https://github.com/fullofcaffeine/hxhx/commit/af2a6d9287e02c0a7b6560a14df41ea85f59060b))
* **hih-compiler:** add stage1 lexer/parser subset ([0b267a7](https://github.com/fullofcaffeine/hxhx/commit/0b267a7330140b6f483b1a51d8c3f4c45df465d5))
* **hih-compiler:** expand lexer/parser subset ([0c21c0b](https://github.com/fullofcaffeine/hxhx/commit/0c21c0b61f9f7af286ae74890bae773ba75c1cca))
* **hih:** add lambda expr + stable keyword text ([d16276b](https://github.com/fullofcaffeine/hxhx/commit/d16276b8093fd56c8e1ea28a1a96aad8e24a12d3))
* **hih:** infer literal return types ([e0c6a8c](https://github.com/fullofcaffeine/hxhx/commit/e0c6a8c6dfc698e30d21ee4686a29caac5a182f1))
* **hih:** native frontend typed args ([2678847](https://github.com/fullofcaffeine/hxhx/commit/26788474614246f834e72b4afe599d56065eb0bb))
* **hih:** preserve try/catch expr shape ([d603a61](https://github.com/fullofcaffeine/hxhx/commit/d603a612ee67d8ff732a22933d32b3e1c4189650))
* **hih:** rehydrate native method bodies ([65d6845](https://github.com/fullofcaffeine/hxhx/commit/65d684569be353cefee5a422b8ec04442bf4c275))
* **hxhx:** add --target presets + bundled dist libs ([331efbf](https://github.com/fullofcaffeine/hxhx/commit/331efbfb82252d85bca898d769d40bae00814bb1))
* **hxhx:** add @:build bring-up rung ([437fef6](https://github.com/fullofcaffeine/hxhx/commit/437fef6db934f265d5dfbdd9c71cb9670936ac5a))
* **hxhx:** add gate2 stage3 driver mode ([aa655c7](https://github.com/fullofcaffeine/hxhx/commit/aa655c7db7ca79eea491359662a55fd10a84972d))
* **hxhx:** add include() macro rung ([7fa0b83](https://github.com/fullofcaffeine/hxhx/commit/7fa0b8354c13853b8c189c303dca6017d762fc4f))
* **hxhx:** add macro arg entrypoints + stage3 emit rung ([6b135b0](https://github.com/fullofcaffeine/hxhx/commit/6b135b03ad0f4770e6faa3b46b8644fa4382e846))
* **hxhx:** add macro host RPC selftest ([e29c9b1](https://github.com/fullofcaffeine/hxhx/commit/e29c9b12bf835eed8b3e7936293e15d18f8029c8))
* **hxhx:** add stage1 --no-output bring-up ([f5a8aee](https://github.com/fullofcaffeine/hxhx/commit/f5a8aee1482137866a40559de5f119da8baa66d4))
* **hxhx:** add stage1 parse/selftest flags ([53485c9](https://github.com/fullofcaffeine/hxhx/commit/53485c9d98f7132116684abad92a2139fe7e7001))
* **hxhx:** add stage3 --hxhx-no-emit rung ([ffd7ad1](https://github.com/fullofcaffeine/hxhx/commit/ffd7ad11997253de46e50d660630b1ddb896e880))
* **hxhx:** add stage3 --hxhx-no-run ([c713008](https://github.com/fullofcaffeine/hxhx/commit/c713008305da232dbb76e59f16cad956d361444a))
* **hxhx:** add stage3 socket wait/connect transport ([7ca5cef](https://github.com/fullofcaffeine/hxhx/commit/7ca5cefe4397165726afd60fd46c5e8ec5cb9020))
* **hxhx:** allow basic operators in stage3 return emission ([ab79e38](https://github.com/fullofcaffeine/hxhx/commit/ab79e38c5dc73d9b0eaa22f1ae2d39b250ef9cc6))
* **hxhx:** duplex macro RPC define roundtrip ([c89b7d1](https://github.com/fullofcaffeine/hxhx/commit/c89b7d16f93b2faf633c6d7f3b810a2ef3828f99))
* **hxhx:** emit basic boolean/int ops in stage3 ([4e6ab36](https://github.com/fullofcaffeine/hxhx/commit/4e6ab36dd5b4f4cfa53716c8536463956cc11790))
* **hxhx:** expand Array<Field> build-macro printing ([45839cc](https://github.com/fullofcaffeine/hxhx/commit/45839cc121f9291d20acb15b47de49d7258368d7))
* **hxhx:** expression macro expansion rung ([346b761](https://github.com/fullofcaffeine/hxhx/commit/346b7614ceb41008cafabb79113e0c80ef612427))
* **hxhx:** filter #if branches in resolver ([075fc75](https://github.com/fullofcaffeine/hxhx/commit/075fc750e371c8a537bfa84f6d9205415bcf447a)), closes [#if](https://github.com/fullofcaffeine/hxhx/issues/if)
* **hxhx:** full-body Stage3 emission via hx parser ([fb2a6f2](https://github.com/fullofcaffeine/hxhx/commit/fb2a6f265a934f72a3dd5f7e4fb933b0429d45d8))
* **hxhx:** genModule includes Context.getType ([b839bbd](https://github.com/fullofcaffeine/hxhx/commit/b839bbd6dcff57ac7b3ef93b42441ea9ec7d4aac))
* **hxhx:** improve Gate2 runci bring-up ([eb211fc](https://github.com/fullofcaffeine/hxhx/commit/eb211fc6be76f6902346e0a2970cc017be6ab3ba))
* **hxhx:** improve stage3 display request handling ([6729f42](https://github.com/fullofcaffeine/hxhx/commit/6729f4276ed43e07d55221944fa55186c673421c))
* **hxhx:** macro addClassPath affects resolution ([b24b11f](https://github.com/fullofcaffeine/hxhx/commit/b24b11f85a59616b11247595278895b5d3e4f7b1))
* **hxhx:** macros can emit extra OCaml modules ([2b546a1](https://github.com/fullofcaffeine/hxhx/commit/2b546a1d6f79d9861e99750eb871b5a91edcf092))
* **hxhx:** macros can emit Haxe modules ([577b7de](https://github.com/fullofcaffeine/hxhx/commit/577b7de25254963eb06f5ac157fb07475e60663d))
* **hxhx:** native lexer/parser hooks ([b645e7d](https://github.com/fullofcaffeine/hxhx/commit/b645e7d76e73847289bf5b9ec9fb34dca17c4126))
* **hxhx:** ocaml interp emulation runner ([44c22d2](https://github.com/fullofcaffeine/hxhx/commit/44c22d2bf490226a88a56d3ce9bd5fa28b3da3ab))
* **hxhx:** persist macro defines in compiler state ([a16d583](https://github.com/fullofcaffeine/hxhx/commit/a16d583caa7f679c2cc0a3bd4cd1707516fa2e9e))
* **hxhx:** route standard --js/-js to native js backend ([94fa40d](https://github.com/fullofcaffeine/hxhx/commit/94fa40d8b8d7677027bb104fa978f5bb9778cf7c))
* **hxhx:** run stage3 --macro via macro host ([8fcc0b1](https://github.com/fullofcaffeine/hxhx/commit/8fcc0b12860e07c1338552a552270db04441aedb))
* **hxhx:** seed -D defines for macros ([f0ff96f](https://github.com/fullofcaffeine/hxhx/commit/f0ff96ffda065a3f87584bb4c77b617737dc0660))
* **hxhx:** stage1 accept -D/-lib/--macro ([757254f](https://github.com/fullofcaffeine/hxhx/commit/757254f80f1b21b0883ada24e6b6a8c738a5d6e2))
* **hxhx:** stage1 parse import closure ([98cfa9e](https://github.com/fullofcaffeine/hxhx/commit/98cfa9e671fa2cfc7db86fca212284faf0f9a38b))
* **hxhx:** stage3 class surface typing ([c8ce23c](https://github.com/fullofcaffeine/hxhx/commit/c8ce23cd5929d6de50084f8c8bf5f7252dbf1b54))
* **hxhx:** stage3 emitter ocaml injection ([fd3be61](https://github.com/fullofcaffeine/hxhx/commit/fd3be616042f54854a7421c00de6e708495496ee))
* **hxhx:** stage3 for-in scaffolding + gate2 emit-runner checks ([767b0f6](https://github.com/fullofcaffeine/hxhx/commit/767b0f6bca2f4a3d19e5cf1fd7ef5fd3458cb68c))
* **hxhx:** stage3 honors --interp ([9e0d901](https://github.com/fullofcaffeine/hxhx/commit/9e0d90187c3bf1d386151f489113a09c7c5eaab5))
* **hxhx:** stage3 supports --next hxml ([e5199fd](https://github.com/fullofcaffeine/hxhx/commit/e5199fd49682c71d6d451820a23c9cb730f24cb7))
* **hxhx:** stage3 Sys.command + process readLine ([8e35b5e](https://github.com/fullofcaffeine/hxhx/commit/8e35b5e6fe4d8a1eb3fb0d31a7b90f0c86222d5a))
* **hxhx:** stage3 typer locals + unify ([4a62d6e](https://github.com/fullofcaffeine/hxhx/commit/4a62d6ef1f7654e9e8556d9d312504d326b18db0))
* **hxhx:** strengthen stage3 full-body emit rung ([5d86b8a](https://github.com/fullofcaffeine/hxhx/commit/5d86b8a4e380ba3cafdfffea89213890d764ae2a))
* **hxhx:** support build macro field replacements ([6629caa](https://github.com/fullofcaffeine/hxhx/commit/6629caae52498c5d41b4d3dd75e79336bcc8629c))
* **hxhx:** support build macros returning fields ([c91b2ff](https://github.com/fullofcaffeine/hxhx/commit/c91b2ff003b2e5b88e4a921e6eaaf5c78673d438))
* **hxhx:** unblock upstream stage3 type-only ([24cfbc8](https://github.com/fullofcaffeine/hxhx/commit/24cfbc837b24fd694a9c14fc7dad5a4e95b44836))
* **hxhx:** versioned native frontend protocol ([b76dd7b](https://github.com/fullofcaffeine/hxhx/commit/b76dd7bf41f891b106f7f2809173652c821a9051))
* **interop:** add ExtLib PMap externs ([b717f80](https://github.com/fullofcaffeine/hxhx/commit/b717f80754b0b129c7abcecc9c63eda11acb1926))
* **interop:** extern @:native module/function mapping ([6f32e53](https://github.com/fullofcaffeine/hxhx/commit/6f32e53d1432c9297e2a9a53442350e7d7bf5463))
* **interop:** labelled/optional extern args ([8d05b1a](https://github.com/fullofcaffeine/hxhx/commit/8d05b1a7d74f555cdd13720d6391e85e38b946ee))
* **js-native:** expand parity fixtures and reflection helpers ([f3d8b8d](https://github.com/fullofcaffeine/hxhx/commit/f3d8b8d16852e91c7d9ec3e7ca5849b99e18a472))
* **m10:** ++/-- for Float and nullable primitives ([651a756](https://github.com/fullofcaffeine/hxhx/commit/651a7565683fac6d87751228382b5f495b19ba30))
* **m10:** anonymous structures via HxAnon ([cb6b648](https://github.com/fullofcaffeine/hxhx/commit/cb6b648b22bfeee33a6013161e7c94ef5a407810))
* **m10:** do-while lowering ([0cda41f](https://github.com/fullofcaffeine/hxhx/commit/0cda41f36a74014c61ab7bd062e44cad82fe16b7))
* **m10:** dynamic fields + Reflect.field ([75daa57](https://github.com/fullofcaffeine/hxhx/commit/75daa5725dc97cbd4344bd953bb18497174f1448))
* **m10:** enable dispatch for upstream stdlib ([7ba3d12](https://github.com/fullofcaffeine/hxhx/commit/7ba3d12879d2ee201a6e36cdbf1d473c490f8d68))
* **m10:** inheritance + multi-type module scoping ([a151390](https://github.com/fullofcaffeine/hxhx/commit/a1513905c8f6f1fcd3d7b0fb8aed0ff6a1aa76e5))
* **m10:** interfaces + dynamic dispatch ([116b745](https://github.com/fullofcaffeine/hxhx/commit/116b74500c7a829439b4439188a75af035956b25))
* **m10:** method-as-value (bound closures) ([bc7d688](https://github.com/fullofcaffeine/hxhx/commit/bc7d6889d8e6328d4919bed729dc1332d50591a6))
* **m10:** runtime RTTI typed catches ([1146528](https://github.com/fullofcaffeine/hxhx/commit/114652859a5439c29ee1d251598d08d6314ee902))
* **m10:** Type.getClass (runtime class identity) ([ae98eb1](https://github.com/fullofcaffeine/hxhx/commit/ae98eb1608196989cd219de122a12fcc434cb3bc))
* **m10:** Type.getClassName/resolveClass + type expr ([c96f4e8](https://github.com/fullofcaffeine/hxhx/commit/c96f4e8e87194d419a3441026c785d1eb2e0c8a6))
* **m10:** typed catches via tagged throws ([676cc55](https://github.com/fullofcaffeine/hxhx/commit/676cc55a90b14f64dcd4ad7cc1b92a870f74ff0a))
* **m10:** typed-catch tags for enums/primitives ([fe61413](https://github.com/fullofcaffeine/hxhx/commit/fe61413b0b77ddc54dc9c7382738e0fb77a7b0f3))
* **m11:** Int32 semantics, EReg+Math runtime ([e3c4966](https://github.com/fullofcaffeine/hxhx/commit/e3c49669031b5c1573b504ec7d156cc779078666))
* **ocaml-native:** add functor-backed Map/Set surfaces ([d3be69c](https://github.com/fullofcaffeine/hxhx/commit/d3be69ceeac6f8b475388770613f1f93abc9e4db))
* **ocaml-native:** docs + example + typed Stdlib wrappers ([926b2c4](https://github.com/fullofcaffeine/hxhx/commit/926b2c4b144ba41a4bcd13ed8b1cb6ea251e8285))
* **ocaml-native:** map ocaml.* abstracts to native types ([31ef805](https://github.com/fullofcaffeine/hxhx/commit/31ef80557cfdb43b97e5da743b8c46eb821f79fa))
* **output:** detect module name collisions ([8fbbd3a](https://github.com/fullofcaffeine/hxhx/commit/8fbbd3a95419609bf639c37e710016acb27d9add))
* **output:** emit OCaml package alias modules ([5f3969f](https://github.com/fullofcaffeine/hxhx/commit/5f3969f97bdc84c09ac6b6cd8ec9ffe7d27298db))
* **stage3:** improve string emission ([dd78f69](https://github.com/fullofcaffeine/hxhx/commit/dd78f69a330aa42e2813b15538ffd53dc0965219))
* **stage3:** infer Array element types ([a654bd6](https://github.com/fullofcaffeine/hxhx/commit/a654bd610c1359967045c9c1ccd94aa5b77cf847))
* **stage3:** lazy module loading in typer ([b6fa29c](https://github.com/fullofcaffeine/hxhx/commit/b6fa29cd48086513083bcde814dcb8761d54c07b))
* **stage3:** string ternary printing ([4f6116b](https://github.com/fullofcaffeine/hxhx/commit/4f6116b519b616680e379bf08955ef246ebd2684))
* **stage3:** switch raw + string interpolation ([7c1cc56](https://github.com/fullofcaffeine/hxhx/commit/7c1cc56ffa6517ee92e85a621924367ef882fffe))
* **stage4:** bootstrap macro host without stage0 ([bc8d26f](https://github.com/fullofcaffeine/hxhx/commit/bc8d26f7d134b57c07e9c614601f2697dec967f3))
* **std/ocaml:** add Array/Bytes/Hashtbl/Seq APIs ([c5bb3f9](https://github.com/fullofcaffeine/hxhx/commit/c5bb3f9eeb584a6e8e43e4a67a55caf41a5e15a0))
* stdio streams, mutable statics, macro pos ([bd8e288](https://github.com/fullofcaffeine/hxhx/commit/bd8e2886f4fe81f5df824e5bcb0a97f23ff07b9e))
* **tooling:** add ocaml_sourcemap directives ([3e3d236](https://github.com/fullofcaffeine/hxhx/commit/3e3d2361ea368ca9b3f346d98bbd4ff4f57b3147))
* **tooling:** dune lib layout and multi-exe ([dab6d64](https://github.com/fullofcaffeine/hxhx/commit/dab6d64a80a190bd241f8fa5026f40260beef53a))
* **tooling:** infer .mli via ocamlc -i ([66b4cb2](https://github.com/fullofcaffeine/hxhx/commit/66b4cb27f16cc73562efa7dd05d202abc328f97b))
* **tooling:** ocaml_mli=all ([3986d13](https://github.com/fullofcaffeine/hxhx/commit/3986d1384724dc98af6a2eda4d73ec3dea0bf580))
* **tooling:** stable OCaml error locations ([febfa81](https://github.com/fullofcaffeine/hxhx/commit/febfa81128529df05010b107ec1b103734244d88))


### Performance Improvements

* **builder:** avoid refs via let-shadowing ([28ef3c2](https://github.com/fullofcaffeine/hxhx/commit/28ef3c2549ffa910e8fbe5d2cda780c0bb5a27ef))
* **std:** implement StringBuf via Stdlib.Buffer ([e664b3d](https://github.com/fullofcaffeine/hxhx/commit/e664b3d43b90288ebc9f22cac82efe7a74ce5659))

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
