# [0.34.0](https://github.com/fullofcaffeine/hxhx/compare/v0.33.4...v0.34.0) (2026-08-30)


### Bug Fixes

* **ci:** bound Core test shard workloads ([a32058c](https://github.com/fullofcaffeine/hxhx/commit/a32058cc57770a3891e87a635ba314d624bcaf47))
* **ci:** reconcile closed evidence incidents ([d618702](https://github.com/fullofcaffeine/hxhx/commit/d6187023c40fc65787b43537f80e3eb95d92f420))
* **evidence:** report evaluator GC overflow honestly ([255fb4e](https://github.com/fullofcaffeine/hxhx/commit/255fb4e0f0a280b1151b659b190b8bfb300f164b))
* **hxhx:** box compiler JSON number results ([5a943f1](https://github.com/fullofcaffeine/hxhx/commit/5a943f111008a7ac2f9fe5e37752cdb35f9f11cb))
* **hxhx:** box concrete stub returns ([0cf4185](https://github.com/fullofcaffeine/hxhx/commit/0cf4185eebee4df81db7b3f5a5b287eb38bdaaed))
* **hxhx:** box qualified Dynamic arguments ([f1fefd0](https://github.com/fullofcaffeine/hxhx/commit/f1fefd02ad8156860dccacca57d608fa70ee6cc4))
* **hxhx:** check Dynamic operators in Stage3 ([e850430](https://github.com/fullofcaffeine/hxhx/commit/e850430ef7904e72c1d60d234b1e57a2fabd70b2))
* **hxhx:** emit primary abstract static functions ([6dc7f1d](https://github.com/fullofcaffeine/hxhx/commit/6dc7f1db7e73d7a12bcb634f65230a0a1dd560de))
* **hxhx:** filter multiline inline conditionals ([c734614](https://github.com/fullofcaffeine/hxhx/commit/c734614f4c9f463b48189013516d2a3434a52651))
* **hxhx:** isolate extension call inference ([5d09d04](https://github.com/fullofcaffeine/hxhx/commit/5d09d04b647cf3e285e6938b329f8080c9cca9dd))
* **hxhx:** keep imports module-local ([3cf43a3](https://github.com/fullofcaffeine/hxhx/commit/3cf43a3f579b1a67d69baf333c89b4281f9ca3fa))
* **hxhx:** keep untyped temporaries unknown ([3ee687c](https://github.com/fullofcaffeine/hxhx/commit/3ee687c4f19cceab7be672d722925c9893436952))
* **hxhx:** order exact instance callees ([7ffaa87](https://github.com/fullofcaffeine/hxhx/commit/7ffaa870d61974bdbefa2525bd8017c2fcaca93c))
* **hxhx:** parse nested anonymous typedefs ([ef16bcb](https://github.com/fullofcaffeine/hxhx/commit/ef16bcb008f38253cc663485952ba46c89e55727))
* **hxhx:** preserve abstract call carriers ([05f130b](https://github.com/fullofcaffeine/hxhx/commit/05f130b4e436dc4991840df80e5a2a6d9480dec6))
* **hxhx:** preserve concrete try results ([26f3109](https://github.com/fullofcaffeine/hxhx/commit/26f310992ea5135764615fd18004be21a07e2de3))
* **hxhx:** preserve explicit OCaml string casts ([21a7391](https://github.com/fullofcaffeine/hxhx/commit/21a7391d1fd9a29869dd3a423fd82bca5bc127de))
* **hxhx:** preserve function argument metadata ([03606b0](https://github.com/fullofcaffeine/hxhx/commit/03606b0af50393a39e18819a31dbd0a150e90058))
* **hxhx:** preserve local Context.load callable arity ([41ec1a4](https://github.com/fullofcaffeine/hxhx/commit/41ec1a4d00dabd9d8d2fc30fbb73b37b20fe96ce))
* **hxhx:** preserve native expression order ([afd941e](https://github.com/fullofcaffeine/hxhx/commit/afd941e30a47ebab3a07cc2133dbc8a8aaff1b47))
* **hxhx:** preserve returned callable boundaries ([594dc0f](https://github.com/fullofcaffeine/hxhx/commit/594dc0fd810ee9436ac5a97fea85afe637d2921b))
* **hxhx:** preserve typed Stage3 call arguments ([d5092fb](https://github.com/fullofcaffeine/hxhx/commit/d5092fbc1de8def51a03c8bd4021ba71eb897742))
* **hxhx:** preserve wrapped String keys ([5ec3460](https://github.com/fullofcaffeine/hxhx/commit/5ec34601f0e9d2d3c72ce242410deadaa9ac90c2))
* **hxhx:** redact private macro define values ([9866889](https://github.com/fullofcaffeine/hxhx/commit/98668896ae4918bb006a137f0ec91077631bea5b))
* **hxhx:** refine inferred method returns ([c40adc1](https://github.com/fullofcaffeine/hxhx/commit/c40adc1c4a78584b9654f8208876e3cb712ce64c))
* **hxhx:** regenerate current bootstrap snapshot ([36aef8b](https://github.com/fullofcaffeine/hxhx/commit/36aef8b81c72bd5d52ef84f7ddbdc81e12aff2f2))
* **hxhx:** resolve inherited bare method calls ([6ca2e7e](https://github.com/fullofcaffeine/hxhx/commit/6ca2e7e1a205cd0984df6898b55ceb0374ab2204))
* **hxhx:** type nullable numeric updates before null safety ([6fcaa0e](https://github.com/fullofcaffeine/hxhx/commit/6fcaa0e72f2a1b48cd45a36bd2a879ebf09602f3))
* **ocaml:** align nullable string return carriers ([b347a62](https://github.com/fullofcaffeine/hxhx/commit/b347a625ba5c3454909f34a3ccca113442ecab97))
* **ocaml:** authenticate sealed local conversions ([39c3a21](https://github.com/fullofcaffeine/hxhx/commit/39c3a21e37c6b4e1e1e6d2af8166dabedeaf76fc))
* **ocaml:** authorize array iterator runtime uses ([0b93507](https://github.com/fullofcaffeine/hxhx/commit/0b93507261af36f56baf8575f848908b6cc10349))
* **ocaml:** authorize exact String null defaults ([c68ca59](https://github.com/fullofcaffeine/hxhx/commit/c68ca59b844e5db176b917b36bb74de7b7f1a5b8))
* **ocaml:** authorize fallback field defaults ([768bbf7](https://github.com/fullofcaffeine/hxhx/commit/768bbf77167df9ef553ad630a3b048d20a232f57))
* **ocaml:** authorize repeated Array output sites ([6476cf3](https://github.com/fullofcaffeine/hxhx/commit/6476cf3e0a8b64b27617f61283f166c931022650))
* **ocaml:** bind control plans to exact source ([9d46b87](https://github.com/fullofcaffeine/hxhx/commit/9d46b87de8d7bbd168ed32c61c143e5f669ba76a))
* **ocaml:** bound exact reuse admission ([775e40b](https://github.com/fullofcaffeine/hxhx/commit/775e40bbbf78108c848dcdc7028856b96fae4c18))
* **ocaml:** canonicalize static string aliases ([8588fd6](https://github.com/fullofcaffeine/hxhx/commit/8588fd69e6aef5eda4ecc298f9d645419fe98cf4))
* **ocaml:** canonicalize String field aliases ([3bc422e](https://github.com/fullofcaffeine/hxhx/commit/3bc422eb181d39481e69ca98469a851ce98a3113))
* **ocaml:** check nullable Array indexes ([af649f3](https://github.com/fullofcaffeine/hxhx/commit/af649f3808ab3f6560d1eb6894a9a0a95b81a819))
* **ocaml:** check nullable map storage aliases ([a285186](https://github.com/fullofcaffeine/hxhx/commit/a2851867abb609b3a8b45c272951293fa230c0a6))
* **ocaml:** close exact-reuse identity gaps ([16e7e9c](https://github.com/fullofcaffeine/hxhx/commit/16e7e9c64b7c189e3814ac2df86c4176f19be84d))
* **ocaml:** close nested literal fallback ([6e55f14](https://github.com/fullofcaffeine/hxhx/commit/6e55f14cff5f45fba5cbf0497fbe7483a5f4316b))
* **ocaml:** close String null fallback paths ([38af21b](https://github.com/fullofcaffeine/hxhx/commit/38af21b966321697311e9ae9e061443b13bf353e))
* **ocaml:** compare nullable strings through typed plan ([f095006](https://github.com/fullofcaffeine/hxhx/commit/f09500606a7f7802dcda2284eacf487751c9dc0f))
* **ocaml:** disambiguate generated array occurrences ([a929c8d](https://github.com/fullofcaffeine/hxhx/commit/a929c8d39ca465368448e100e6a876eaa1e31970))
* **ocaml:** disambiguate runtime String helpers ([cacbbb7](https://github.com/fullofcaffeine/hxhx/commit/cacbbb7dbb27693b1ed4c946b80ed6beb9a140be))
* **ocaml:** distinguish copied nullable switch defaults ([a9424e5](https://github.com/fullofcaffeine/hxhx/commit/a9424e53c6b59dc51b904219f82e9794baf4b779))
* **ocaml:** distinguish copied static string uses ([b2e7c9e](https://github.com/fullofcaffeine/hxhx/commit/b2e7c9eadaee7bfdd6896a8e983d7bf04e59cec5))
* **ocaml:** distinguish copied string method uses ([dcce51b](https://github.com/fullofcaffeine/hxhx/commit/dcce51b1b9628a740c13a1c57ee093344737f30d))
* **ocaml:** distinguish repeated return outputs ([9749cdd](https://github.com/fullofcaffeine/hxhx/commit/9749cddd71138b0b3a1a44db302522df0ac52965))
* **ocaml:** distinguish repeated runtime output sites ([d79cfd6](https://github.com/fullofcaffeine/hxhx/commit/d79cfd62a50469c96918010c3898209d2407af22))
* **ocaml:** fail closed on IMap surface drift ([ff604ca](https://github.com/fullofcaffeine/hxhx/commit/ff604cac182a827d4c0e64d48df6d92b62138015))
* **ocaml:** isolate anonymous literal field helpers ([a02a036](https://github.com/fullofcaffeine/hxhx/commit/a02a0362e40e6b6a632772cf3566744a65d3f8cb))
* **ocaml:** keep constructor slice exact ([fae1b18](https://github.com/fullofcaffeine/hxhx/commit/fae1b18aaa8ec1a6b7c56dcd2376c539514035d9))
* **ocaml:** keep runtime facts framework-free ([6ca77e5](https://github.com/fullofcaffeine/hxhx/commit/6ca77e53bdcc1ea4148fd1d0fe88bd5825469313))
* **ocaml:** keep switch branch identities distinct ([8ed8ac1](https://github.com/fullofcaffeine/hxhx/commit/8ed8ac1232590175b8c469a2dddad44069436a7e))
* **ocaml:** keep Void catch branches unit-valued ([4719dfd](https://github.com/fullofcaffeine/hxhx/commit/4719dfdb83dcae400124539b41cb2db6605067e6))
* **ocaml:** map Haxe enum reflection indices ([f76e69c](https://github.com/fullofcaffeine/hxhx/commit/f76e69c4dab6cc101c1aa51fa2851b46dd7d54fd))
* **ocaml:** match DCE-reduced IMap records ([c84039c](https://github.com/fullofcaffeine/hxhx/commit/c84039c1de8c47d4db6ecd4661b9f68266ffae41))
* **ocaml:** match subclass exceptions safely ([aaa80d5](https://github.com/fullofcaffeine/hxhx/commit/aaa80d51e9de058eb8322d4fa325506a5925a759))
* **ocaml:** normalize inferred nullable strings ([5033ff1](https://github.com/fullofcaffeine/hxhx/commit/5033ff191535313a48025a8b6b3d00a0f30dd34a))
* **ocaml:** order same-module class carriers ([da5a2bd](https://github.com/fullofcaffeine/hxhx/commit/da5a2bd50b82d2694c3acd595c7ade041e3fa448))
* **ocaml:** own repeated String default outputs ([688fe1b](https://github.com/fullofcaffeine/hxhx/commit/688fe1bee5b85be85ccf2b8c62990519880cc9b7))
* **ocaml:** own repeated wildcard switch branches ([21748e5](https://github.com/fullofcaffeine/hxhx/commit/21748e56cbb7b5c6f3f303d410b8a6392c0a5eb4))
* **ocaml:** preserve callable Array read types ([e6dc543](https://github.com/fullofcaffeine/hxhx/commit/e6dc543c51b0d616983a0adc62f04b13266d657c))
* **ocaml:** preserve deferred nested parents ([8f667bd](https://github.com/fullofcaffeine/hxhx/commit/8f667bd2262a73ec37fd6af7fbd324bd1d53bcba))
* **ocaml:** preserve direct typed enum indices ([e80722b](https://github.com/fullofcaffeine/hxhx/commit/e80722bbc635f49876ee99746d4c7974925e7849))
* **ocaml:** preserve enums in Dynamic arrays ([501227e](https://github.com/fullofcaffeine/hxhx/commit/501227e2968fe9bc78ae4d8ba4b8c8dc8acbab5d))
* **ocaml:** preserve final Array helper identities ([a959216](https://github.com/fullofcaffeine/hxhx/commit/a9592160eaacaafe65fff43ea5677dda448ad8a3))
* **ocaml:** preserve generated Void call results ([e354295](https://github.com/fullofcaffeine/hxhx/commit/e3542956a9c62090e334e9b0d6d6791a60916d7b))
* **ocaml:** preserve Map pair projections ([38e5bc1](https://github.com/fullofcaffeine/hxhx/commit/38e5bc15a046319c6544bd2b3d3143c998a142d9))
* **ocaml:** preserve non-completing loop types ([71d8e14](https://github.com/fullofcaffeine/hxhx/commit/71d8e1422e076d6063496040be372b6d7cf924df))
* **ocaml:** preserve null for exact String storage ([1a36210](https://github.com/fullofcaffeine/hxhx/commit/1a362101404c3cc93ac4ae692ab3138c8cf76b1a))
* **ocaml:** preserve nullable anonymous returns ([b522b4c](https://github.com/fullofcaffeine/hxhx/commit/b522b4c211840498126f4fc6c05b182b832d2130))
* **ocaml:** preserve nullable return carriers ([e808b9c](https://github.com/fullofcaffeine/hxhx/commit/e808b9c56b12d21ad52c40c25bead776b5848299))
* **ocaml:** preserve nullable string array concat ([eee727b](https://github.com/fullofcaffeine/hxhx/commit/eee727b93367063020dcf3579dbb621563a38870))
* **ocaml:** preserve root local plan ownership ([d3c4d8e](https://github.com/fullofcaffeine/hxhx/commit/d3c4d8e6fead436d2bd29dd804257c8a73d40529))
* **ocaml:** preserve root place plan ownership ([997cd1b](https://github.com/fullofcaffeine/hxhx/commit/997cd1baec045807559dddc5207cb14f599b99d3))
* **ocaml:** preserve switch-case object plans ([b1df3c0](https://github.com/fullofcaffeine/hxhx/commit/b1df3c061ea16546fbc9323064dc065c006d0b31))
* **ocaml:** preserve typed Map field carriers ([a3341aa](https://github.com/fullofcaffeine/hxhx/commit/a3341aa83e2fe9b953ee10a67225ceabd679cb41))
* **ocaml:** print deep target syntax without recursion ([a9fb54a](https://github.com/fullofcaffeine/hxhx/commit/a9fb54ae7954754a0297ebed5b9bf562ce78336e))
* **ocaml:** prove real exact target hits ([fe50052](https://github.com/fullofcaffeine/hxhx/commit/fe50052f72f07fcb37913f2ce20fa3259189d6b1))
* **ocaml:** reconcile final runtime uses ([5e63f8d](https://github.com/fullofcaffeine/hxhx/commit/5e63f8d2aa17087d271d80b688d059ccc3d93132))
* **ocaml:** reject mismatched array identities ([504b266](https://github.com/fullofcaffeine/hxhx/commit/504b266033d287f44feb0ae96f4bf5d97be4f019))
* **ocaml:** reject missing typed rest arrays ([0da46cd](https://github.com/fullofcaffeine/hxhx/commit/0da46cdcc17205efbf46e414516ecb830658fc72))
* **ocaml:** reject stale control report bindings ([ed591b6](https://github.com/fullofcaffeine/hxhx/commit/ed591b649e12e6c8ce54556446fbfcc0290ca41b))
* **ocaml:** require array plans at syntax ([184393c](https://github.com/fullofcaffeine/hxhx/commit/184393c81d424a7085f1f41ebe30ef5c0e2cff00))
* **ocaml:** require Dynamic array conversions ([498e15f](https://github.com/fullofcaffeine/hxhx/commit/498e15fbff38685f57159a7bb45c356c1466878d))
* **ocaml:** reserve private runtime names in raw code ([7fd3732](https://github.com/fullofcaffeine/hxhx/commit/7fd3732b6b65bf1f6ca17ce72c815e95b14369a9))
* **ocaml:** restore Array runtime authority ([af807b2](https://github.com/fullofcaffeine/hxhx/commit/af807b208dad8a298153696e904ceb4bc2fb6587))
* **ocaml:** restore metal profile performance evidence ([42c5e91](https://github.com/fullofcaffeine/hxhx/commit/42c5e91c77e60b2d235adb23dde6cb573e2699d7))
* **ocaml:** retain nullable string return decisions ([69d992f](https://github.com/fullofcaffeine/hxhx/commit/69d992fc0e157994b4626554abf47ff0e4f6ad1d))
* **ocaml:** seal anonymous compound writes ([9c1950e](https://github.com/fullofcaffeine/hxhx/commit/9c1950e40518c35d76a2a15e283c28fbb2d45071))
* **ocaml:** seal concrete Dynamic call arguments ([1d5024c](https://github.com/fullofcaffeine/hxhx/commit/1d5024c6930ed5674b98e98b4638c31cc15417f5))
* **ocaml:** seal Dynamic arrays in field initializers ([bb1f0e2](https://github.com/fullofcaffeine/hxhx/commit/bb1f0e2482e45f345de3e50e4ae8fb126637cd8a))
* **ocaml:** seal enum values entering Dynamic ([ef871a6](https://github.com/fullofcaffeine/hxhx/commit/ef871a62ef2d0e2b05da9eeea4d66042dc2cf137))
* **ocaml:** seal loop and dynamic bracket runtime use ([3e56295](https://github.com/fullofcaffeine/hxhx/commit/3e562958921853ff2f89ca66633b6b0e86a44288))
* **ocaml:** seal nested nullable enum results ([6470ea0](https://github.com/fullofcaffeine/hxhx/commit/6470ea0b707c8ffd320dfbfa9bf7cade941e7476))
* **ocaml:** seal nullable Boolean results ([e359b31](https://github.com/fullofcaffeine/hxhx/commit/e359b31b148a7956440d318337e493db3e0a9e3e))
* **ocaml:** seal nullable enum function results ([713a8d6](https://github.com/fullofcaffeine/hxhx/commit/713a8d60baf2eb46a0ce5151d5242232a527570d))
* **ocaml:** seal standard map storage aliases ([be97284](https://github.com/fullofcaffeine/hxhx/commit/be972848d34348fcabeb731bf7c6739fc6854a1e))
* **ocaml:** seal static nullable enum results ([da63eb2](https://github.com/fullofcaffeine/hxhx/commit/da63eb26df86cd7ce23f64c8e1a4272ad0e18985))
* **ocaml:** seal typed Reflect.compare domains ([0de409e](https://github.com/fullofcaffeine/hxhx/commit/0de409e7135527d167f51a9624ac041ac1736c32))
* **ocaml:** seal Void results for legacy catches ([4dcaa31](https://github.com/fullofcaffeine/hxhx/commit/4dcaa314240f6a4a1ecf389e1b226b4c1c271512))
* **ocaml:** share repeated runtime output ownership ([09e0250](https://github.com/fullofcaffeine/hxhx/commit/09e0250dba3ca938fe6e945bcaff3ebd6132bc0a))
* **ocaml:** skip unobservable local defaults ([44c7b43](https://github.com/fullofcaffeine/hxhx/commit/44c7b4346821b5f95b3ee81e46bc2a7b64386b15))
* **ocaml:** stabilize IMap conversion identities ([ff9ab75](https://github.com/fullofcaffeine/hxhx/commit/ff9ab7546082ce018dba1681df1a686bff1616e7))
* **ocaml:** stabilize lowered local identities ([3ed0dc8](https://github.com/fullofcaffeine/hxhx/commit/3ed0dc856a758cd0e28c991430f65a5e369db7ca))
* **ocaml:** type complete return boundaries ([30b0d19](https://github.com/fullofcaffeine/hxhx/commit/30b0d19962a70ebe2adf6c98e3b26b5981e56e2b))
* **ocaml:** type early-return recovery ([d29f086](https://github.com/fullofcaffeine/hxhx/commit/d29f086a5105ad8ac48cdf2a0b46a9755ff8c5e8))
* **ocaml:** validate marker-backed dynamic arrays ([db670e4](https://github.com/fullofcaffeine/hxhx/commit/db670e4aaf52ece67eb73e6157bb83c084dcb9f5))
* **ocaml:** validate nullable field-default evidence ([a409a98](https://github.com/fullofcaffeine/hxhx/commit/a409a9811d31c7432e339fc4fb1a8826fe10e722))
* **parser:** preserve static across conditional modifiers ([3de0493](https://github.com/fullofcaffeine/hxhx/commit/3de04934f3ef655f1a7f2a014a5cf004a6b9f366))
* **reflaxe-ocaml:** authorize Reflect field helpers ([3d1ab86](https://github.com/fullofcaffeine/hxhx/commit/3d1ab86fc974119c72ad1deedb5b5565bbefca9e))
* **reflaxe-ocaml:** isolate executable entry modules ([2ac64c1](https://github.com/fullofcaffeine/hxhx/commit/2ac64c19bc4cef3fa08bcf145f1c3e48fa9e548c))
* **reflaxe-ocaml:** keep Bytes policy out of runtime ledger ([519c290](https://github.com/fullofcaffeine/hxhx/commit/519c290d9e8b82e9ed5f64d828e54647c87d0926))
* **reflaxe-ocaml:** keep generic iterator calls direct ([ee89ca0](https://github.com/fullofcaffeine/hxhx/commit/ee89ca0f524e0b21768a50f2a72c61c7bd177e0c))
* **reflaxe-ocaml:** keep shared plan identity stable ([d2ff47b](https://github.com/fullofcaffeine/hxhx/commit/d2ff47b301c2df49bb19fc2f4a60712f3a61cad4))
* **reflaxe-ocaml:** preserve generic identity carriers ([377fffd](https://github.com/fullofcaffeine/hxhx/commit/377fffd2d7a157b777d7bc10b52ca1e7b848f7c2))
* **reflaxe-ocaml:** preserve grouped enum patterns ([37f3ecb](https://github.com/fullofcaffeine/hxhx/commit/37f3ecb64ae6721ce73387fd1acda8c013cdb191))
* **reflaxe-ocaml:** preserve malformed URL escapes ([9b7ecdb](https://github.com/fullofcaffeine/hxhx/commit/9b7ecdbfe2f2cab44781d67b2fe1f64264367335))
* **reflaxe-ocaml:** preserve optional dynamic values ([7cb26de](https://github.com/fullofcaffeine/hxhx/commit/7cb26dec9d4b183d5c14444708b1c6ba23301c93))
* **reflaxe-ocaml:** preserve string concat order ([8438c57](https://github.com/fullofcaffeine/hxhx/commit/8438c5797364d53587449086254aa6f961d20302))
* **reflaxe-ocaml:** prove native map pair fields ([afdff69](https://github.com/fullofcaffeine/hxhx/commit/afdff69ae9ce921634d4e3c38c5ac39e71f5ae06))
* **reflaxe-ocaml:** qualify same-module toString calls ([c0e4b78](https://github.com/fullofcaffeine/hxhx/commit/c0e4b7814e4ca9de03659bf436f9e301e29dc6f7))
* **reflaxe-ocaml:** reflect array class tokens ([64ce65d](https://github.com/fullofcaffeine/hxhx/commit/64ce65d01324993a9fad89a26053a84eface940d))
* **reflaxe-ocaml:** reject forged instance receivers ([62dcd92](https://github.com/fullofcaffeine/hxhx/commit/62dcd921eba97975ae518e8370a92aab6aeb8750))
* **reflaxe-ocaml:** resolve nested call occurrences ([05f0186](https://github.com/fullofcaffeine/hxhx/commit/05f01866ac17a0caeadd69e15c5a076725a6e6f6))
* **reflaxe-ocaml:** type key-value field ownership ([1a05d9f](https://github.com/fullofcaffeine/hxhx/commit/1a05d9f5f1908abcc52e43ec5c6b6c7b4dc2554f))
* **reflaxe-ocaml:** unify StringTools URL codecs ([2f821d7](https://github.com/fullofcaffeine/hxhx/commit/2f821d7e72e49663a679bc1c7ef5d66a08997812))
* **reflaxe-ocaml:** validate typed compare dependencies ([7e1c0fc](https://github.com/fullofcaffeine/hxhx/commit/7e1c0fce315e8d225645f249d563ff6b1c429550))
* **reflaxe.ocaml:** seal array receiver representations ([c6de59a](https://github.com/fullofcaffeine/hxhx/commit/c6de59ad70ac43c24cf1e18734ca512637c80f60))
* **reflaxe.ocaml:** type Array<Int> local rebinding ([0952e27](https://github.com/fullofcaffeine/hxhx/commit/0952e27ad966a5eb0dd81ae300650337cc587895))
* **reflaxe:** accept analyzer local rebindings ([c2fa3ea](https://github.com/fullofcaffeine/hxhx/commit/c2fa3eae98af416d6dc85781501ffca253075094))
* **reflaxe:** align warm reachability facts ([1971dc3](https://github.com/fullofcaffeine/hxhx/commit/1971dc335a3c907196815c471487de1de6629718))
* **reflaxe:** build only after framework publication ([4670dc8](https://github.com/fullofcaffeine/hxhx/commit/4670dc885fd1ca746a735f6ad2f5482bb6e0ef77))
* **reflaxe:** pin complete warm programs ([df4d02e](https://github.com/fullofcaffeine/hxhx/commit/df4d02e7f87598bac66d662dd000433358a32f36)), closes [#15](https://github.com/fullofcaffeine/hxhx/issues/15)
* **reflaxe:** preserve nullable initial bindings ([5dbf634](https://github.com/fullofcaffeine/hxhx/commit/5dbf634ebe9ccd2698647538f987e53c65687f01))
* **reflaxe:** publish warm output transactionally ([b6cc568](https://github.com/fullofcaffeine/hxhx/commit/b6cc568e365c1d63f51ce0d0178fc8bd3acbadf7))
* **reflaxe:** reject transactional mli before staging ([9e634d0](https://github.com/fullofcaffeine/hxhx/commit/9e634d0140d6858f81354b6841cfe152a43cd3fb))
* **reflaxe:** reset source positions per request ([b6fd406](https://github.com/fullofcaffeine/hxhx/commit/b6fd4065b7a1eccfe5c8f79a2d11b9d3df19a6f2))
* **reflaxe:** stabilize warm target request identity ([ac86e06](https://github.com/fullofcaffeine/hxhx/commit/ac86e0651967840fbc3056be7124ec52b2de438a))
* **reuse:** fail closed on unstable Haxe 4 RTTI ([f13de77](https://github.com/fullofcaffeine/hxhx/commit/f13de77fc2dcb410172cfe5c82d8440a4e843c2b))
* **runtime:** classify dynamic strings before arrays ([bb783b0](https://github.com/fullofcaffeine/hxhx/commit/bb783b034d72b6fd9594acb18ddcb7eda3eca4ca))
* **runtime:** keep array sort storage-safe ([e1f0370](https://github.com/fullofcaffeine/hxhx/commit/e1f0370c1f56f3a39db8e3a61155fd96338f3b3e))
* **runtime:** qualify standard List access ([f47d572](https://github.com/fullofcaffeine/hxhx/commit/f47d5722f2838ec60061dcdfc1f5aa9d3d874030))
* **server:** preserve negative compiler-scale evidence ([4e18cff](https://github.com/fullofcaffeine/hxhx/commit/4e18cff20ab30ce8beeb838cfa5acf412756772a))
* **stage3:** clear function shadowing per request ([9e7b9c8](https://github.com/fullofcaffeine/hxhx/commit/9e7b9c84f0988daef320797efa5218af43ce6958))
* **stage3:** convert Dynamic Float arguments safely ([9ef17aa](https://github.com/fullofcaffeine/hxhx/commit/9ef17aad8fb3f27bb6d52009cccbc5b916afd0da))
* **stage3:** honor selected Float call owners ([d0717ea](https://github.com/fullofcaffeine/hxhx/commit/d0717ea46ec8b8f61e032f7bd83669a361ab0bd0))
* **stage3:** preserve Dynamic String additions ([d71d9fb](https://github.com/fullofcaffeine/hxhx/commit/d71d9fb1ba523642f483000f95eee9366d248a93))
* **stage3:** preserve mixed Float multiplication ([c3dd9f9](https://github.com/fullofcaffeine/hxhx/commit/c3dd9f996d5444098e0831d57c4f4b24dbb75c59))
* **stage3:** retain qualified Float call results ([51943e4](https://github.com/fullofcaffeine/hxhx/commit/51943e482ba1f167da9b9216493b1035364cd305))
* **test:** accept typed generic return recovery ([60664b0](https://github.com/fullofcaffeine/hxhx/commit/60664b0018b0e269b23a39ac6da0af0066852a93))
* **test:** isolate snapshot compiler stdin ([643dd1d](https://github.com/fullofcaffeine/hxhx/commit/643dd1d1602479efa5c7aa5cd062a9226001db11))
* **test:** isolate the Dynamic operator oracle ([b13ffe7](https://github.com/fullofcaffeine/hxhx/commit/b13ffe737d7c299516f78ee99e26f5be36ab6f5f))
* **tooling:** configure Haxe before loading the project ([a061dd8](https://github.com/fullofcaffeine/hxhx/commit/a061dd8d7adf742ae2e083f7b07670170f0eaf1a))
* **typer:** preserve concrete returns after unresolved exits ([c08e577](https://github.com/fullofcaffeine/hxhx/commit/c08e57796cd52595cceef587722fb58aedacb4a0))


### Features

* **ocaml:** activate String array literal throws ([ff3d247](https://github.com/fullofcaffeine/hxhx/commit/ff3d24763a99d298b0af8819b287736073588a27))
* **ocaml:** admit positive-arity sealed static calls ([9907eee](https://github.com/fullofcaffeine/hxhx/commit/9907eee905657bd09c9da332ca3e7f8de7a8daed))
* **ocaml:** authorize anonymous runtime uses ([469711f](https://github.com/fullofcaffeine/hxhx/commit/469711ff40a90edf08a75020b2d997f43d9efa48))
* **ocaml:** authorize Array and Bytes carrier types ([2ef6be5](https://github.com/fullofcaffeine/hxhx/commit/2ef6be573cde3885d25e16085a7e53c31d6d99f3))
* **ocaml:** authorize array literal runtime uses ([cb42da0](https://github.com/fullofcaffeine/hxhx/commit/cb42da0e4d07e9dc29e4f097fb5479affeef7c8c))
* **ocaml:** authorize assignment Int additions ([b709fd2](https://github.com/fullofcaffeine/hxhx/commit/b709fd21f2377a9d6e0a922d82e5d30e5a96890f))
* **ocaml:** authorize Bytes access runtime uses ([1bb1be8](https://github.com/fullofcaffeine/hxhx/commit/1bb1be840f5cb31e4f3236ac1d4a0d25020ede0a))
* **ocaml:** authorize Bytes mutation runtime uses ([eaa8862](https://github.com/fullofcaffeine/hxhx/commit/eaa88623984323bf6edde2a6078e2f27a1805c47))
* **ocaml:** authorize Bytes producer calls ([66f2b8a](https://github.com/fullofcaffeine/hxhx/commit/66f2b8aab3a54abbce59d34000e59e450a397f28))
* **ocaml:** authorize Bytes read runtime uses ([8095ba0](https://github.com/fullofcaffeine/hxhx/commit/8095ba0574b36f90b185f7e1ffc158e57bfdae49))
* **ocaml:** authorize catch return signals ([4efda50](https://github.com/fullofcaffeine/hxhx/commit/4efda500923145b0c680abb32b1c9608f321c020))
* **ocaml:** authorize catch runtime tag tests ([fc51cd4](https://github.com/fullofcaffeine/hxhx/commit/fc51cd43ed285d1925a26152610cc98ac87291ae))
* **ocaml:** authorize direct Reflect runtime calls ([99119c7](https://github.com/fullofcaffeine/hxhx/commit/99119c73bdeab1bae89e24859c2141e634373acd))
* **ocaml:** authorize dynamic equality runtime uses ([9682b4f](https://github.com/fullofcaffeine/hxhx/commit/9682b4f44e4a944953a31595194cf0e63ee42d39))
* **ocaml:** authorize dynamic string runtime uses ([907bd44](https://github.com/fullofcaffeine/hxhx/commit/907bd443a240c11e26748eed4e93c6b77223178a))
* **ocaml:** authorize generated class markers ([a902cbc](https://github.com/fullofcaffeine/hxhx/commit/a902cbc874d3bb563f849f9ff61111c795f6f96d))
* **ocaml:** authorize IMap adapter runtime uses ([f52cb20](https://github.com/fullofcaffeine/hxhx/commit/f52cb20365b4b16e2b1319dc51ddce47bc0425f4))
* **ocaml:** authorize non-function loop control ([9d65c63](https://github.com/fullofcaffeine/hxhx/commit/9d65c637c316c9b0d5a0493b6c3bf9c8a198862c))
* **ocaml:** authorize nullable IMap runtime uses ([b4c86c0](https://github.com/fullofcaffeine/hxhx/commit/b4c86c07bd7db160fb2e0c7902255a59f05ba863))
* **ocaml:** authorize Reflect.compare runtime throws ([9fb115e](https://github.com/fullofcaffeine/hxhx/commit/9fb115e9ee294d2a58d089cfc56603b087def17b))
* **ocaml:** authorize return boundaries ([0ca52b1](https://github.com/fullofcaffeine/hxhx/commit/0ca52b1aeb0ad7042c62e40cf556c722603aeceb))
* **ocaml:** authorize sealed return signals ([7e63b77](https://github.com/fullofcaffeine/hxhx/commit/7e63b77811dfb6c25099ef33da549bc2c976d9e5))
* **ocaml:** authorize sealed throw runtime calls ([e0d6f58](https://github.com/fullofcaffeine/hxhx/commit/e0d6f5869578eb65d373d34d689619f4a4b22786))
* **ocaml:** authorize standard Map carrier types ([80d3a43](https://github.com/fullofcaffeine/hxhx/commit/80d3a432bca11e5b9834ecb4cffc462fe149b47c))
* **ocaml:** authorize structural field runtime uses ([054ae7b](https://github.com/fullofcaffeine/hxhx/commit/054ae7b314851bcecc8cb07d8a7c9828608fb6ac))
* **ocaml:** bound source replay payloads ([905982c](https://github.com/fullofcaffeine/hxhx/commit/905982c427b663dc2e7a84b3cede7b81aff633c9))
* **ocaml:** close generated source authority ([5d758fc](https://github.com/fullofcaffeine/hxhx/commit/5d758fcb8ef03fd12291af85db861886d86e1092))
* **ocaml:** complete early source identity ([4c63484](https://github.com/fullofcaffeine/hxhx/commit/4c63484db23494a6ea38eadac10b8cde3a426d69))
* **ocaml:** derive runtime evidence from requirements ([ecbd79f](https://github.com/fullofcaffeine/hxhx/commit/ecbd79f746583d17c86735d30cb2478ce4a7a289))
* **ocaml:** explain file runtime boundaries ([a9fd128](https://github.com/fullofcaffeine/hxhx/commit/a9fd1281fbc80b2f46d78da68c1f6d5115f823b2))
* **ocaml:** explain the process runtime boundary ([3d8a17b](https://github.com/fullofcaffeine/hxhx/commit/3d8a17bb918911180ad5dd9150788aaaf9d697a6))
* **ocaml:** explain thread runtime boundaries ([fa0ae8c](https://github.com/fullofcaffeine/hxhx/commit/fa0ae8ca889c17f69d9bc49cb9ca5bd69111f39e))
* **ocaml:** expose anonymous object evidence ([42a64f1](https://github.com/fullofcaffeine/hxhx/commit/42a64f16b9eb1b82d82a040f8ce594976ea9bdb3))
* **ocaml:** expose blocked control families ([73098a9](https://github.com/fullofcaffeine/hxhx/commit/73098a9866b920f7577f5a5f4924228eeb54316d))
* **ocaml:** hard-cut sealed catch generation ([0cc981d](https://github.com/fullofcaffeine/hxhx/commit/0cc981dc5679a935919730a2bc8eea4547f1c93a))
* **ocaml:** key reuse by exact target sources ([3553a1c](https://github.com/fullofcaffeine/hxhx/commit/3553a1c731b808c203313525bc05e8eacc590798))
* **ocaml:** measure exact target reuse identity ([3d41d39](https://github.com/fullofcaffeine/hxhx/commit/3d41d39645fdbde6e8b9044640f80e594e4aef49))
* **ocaml:** move Map behavior into typed Haxe ([d37dd26](https://github.com/fullofcaffeine/hxhx/commit/d37dd26f675becd44c271c6c42bca7ba37768f67))
* **ocaml:** pack immutable source candidates ([421124e](https://github.com/fullofcaffeine/hxhx/commit/421124ed3e4032fa1cb536faaa300e241b68c327))
* **ocaml:** plan String equality runtime use ([215a9bf](https://github.com/fullofcaffeine/hxhx/commit/215a9bf7db0132e08046e8287cbf9471bd5c5052))
* **ocaml:** preserve nominal closure returns ([2fc28a7](https://github.com/fullofcaffeine/hxhx/commit/2fc28a7d7bde30356138a06bece3f09c09364270))
* **ocaml:** preserve user IMap dispatch ([a55af7f](https://github.com/fullofcaffeine/hxhx/commit/a55af7fffe29417e41e66e4d0671fae5fd6203a2))
* **ocaml:** prove compiler-scale target reuse ([9d3e60f](https://github.com/fullofcaffeine/hxhx/commit/9d3e60f73716ab87f40ea85c798d4de82ce9101c))
* **ocaml:** prove dormant String array descriptors ([a962dfb](https://github.com/fullofcaffeine/hxhx/commit/a962dfb5fde523a2a0aadfa83bd32040daeb9031))
* **ocaml:** prove dormant String array literal plans ([74c98cb](https://github.com/fullofcaffeine/hxhx/commit/74c98cb239d76810b5a31265275b97790a208997))
* **ocaml:** prove String array element storage ([083e2c4](https://github.com/fullofcaffeine/hxhx/commit/083e2c4dc87436def42406583adc2f84aeb2e7ba))
* **ocaml:** replay exact target source bundles ([7584b0a](https://github.com/fullofcaffeine/hxhx/commit/7584b0a5041564d2770e25b4d4e543da3fe296fa))
* **ocaml:** report requirements-only runtime selection ([b92645d](https://github.com/fullofcaffeine/hxhx/commit/b92645dcf80204833026b472da2e859b1e60b73a))
* **ocaml:** seal Array concat and copy calls ([4535de5](https://github.com/fullofcaffeine/hxhx/commit/4535de58af3e9af959c88851883744f3c4ccb5c6))
* **ocaml:** seal Array indexed searches ([919016f](https://github.com/fullofcaffeine/hxhx/commit/919016f06881b06643756742aacd37db9f04832c))
* **ocaml:** seal Array map and filter calls ([ff0b2ed](https://github.com/fullofcaffeine/hxhx/commit/ff0b2ed7e8e3d4022b3de07822dd5956adccb63f))
* **ocaml:** seal Array membership calls ([918bd28](https://github.com/fullofcaffeine/hxhx/commit/918bd280382d46703a5671d75ddf776d4caa4f41))
* **ocaml:** seal Array mutation calls ([37cdadb](https://github.com/fullofcaffeine/hxhx/commit/37cdadb60ac85954ce9574816453614ead799aae))
* **ocaml:** seal Array resize and splice ([ae33b1a](https://github.com/fullofcaffeine/hxhx/commit/ae33b1a9d21082f5f82fcd217184a0ee3079d405))
* **ocaml:** seal Array slice calls ([c5849d3](https://github.com/fullofcaffeine/hxhx/commit/c5849d36256485010e4bd8d2daf8c7d3ce05c5b9))
* **ocaml:** seal Array sort calls ([bda9348](https://github.com/fullofcaffeine/hxhx/commit/bda93484c24dbd459b661d8a9d4b2426a4b4696a))
* **ocaml:** seal Bool and String early returns ([e9458e0](https://github.com/fullofcaffeine/hxhx/commit/e9458e0c6e72127cebbbcdb8a03862f88c8362d2))
* **ocaml:** seal captured class replacement cells ([a0a08ea](https://github.com/fullofcaffeine/hxhx/commit/a0a08ea756c9fa31ddf84052e6deaac400e79a38))
* **ocaml:** seal checked function boundaries ([c7f0fef](https://github.com/fullofcaffeine/hxhx/commit/c7f0fefaf0b2893c26c927c3c25ed422e1f36d32))
* **ocaml:** seal direct Array bracket reads ([1a49843](https://github.com/fullofcaffeine/hxhx/commit/1a49843a07ee457358abd937cea1105291e8b567))
* **ocaml:** seal direct Array<Int> literals ([8dea989](https://github.com/fullofcaffeine/hxhx/commit/8dea9894c85a855e57403f286aceaf57e389cea9))
* **ocaml:** seal direct enum throws ([b40253c](https://github.com/fullofcaffeine/hxhx/commit/b40253ccb25e69638098749ca61f8db6a8b90755))
* **ocaml:** seal Dynamic function calls ([91eb97a](https://github.com/fullofcaffeine/hxhx/commit/91eb97a9ee448c706cb0dac334ef3e6abab36d2b))
* **ocaml:** seal exact array throws in closures ([4588d2f](https://github.com/fullofcaffeine/hxhx/commit/4588d2f49ca8f4be62d1dc4c3e96bdb909dae121))
* **ocaml:** seal exact Bool call crossings ([ad84c31](https://github.com/fullofcaffeine/hxhx/commit/ad84c3152442c2f099340c08ac51c9a6b0434380))
* **ocaml:** seal exact constructor calls ([8e603e1](https://github.com/fullofcaffeine/hxhx/commit/8e603e146e71b4b4af2354e7c17cf3466a37b384))
* **ocaml:** seal exact Haxe catch chains ([452e313](https://github.com/fullofcaffeine/hxhx/commit/452e31303ad17799e0e0b0f36a1bda3a21989fa2))
* **ocaml:** seal exact Haxe throw payloads ([bae6fa1](https://github.com/fullofcaffeine/hxhx/commit/bae6fa1a310e5e4855bab3c5cec853732d6f7689))
* **ocaml:** seal exact Int early returns ([7314e11](https://github.com/fullofcaffeine/hxhx/commit/7314e11dbd11269353827176e8b372e3c00c949a))
* **ocaml:** seal first direct call family ([31eaf0d](https://github.com/fullofcaffeine/hxhx/commit/31eaf0db11b55ab7142b7aed323bd8ebbe86a4d7))
* **ocaml:** seal Float Bytes access ([0ec4eab](https://github.com/fullofcaffeine/hxhx/commit/0ec4eab859ce853ec0541aa0ad845523cc7e98e9))
* **ocaml:** seal immutable class captures ([68d6bda](https://github.com/fullofcaffeine/hxhx/commit/68d6bda936eb962dc4dbfee86b6d314934c4a208))
* **ocaml:** seal inline Dynamic carriers ([5bd8960](https://github.com/fullofcaffeine/hxhx/commit/5bd8960e3f1ed7177fb13cb9ee12851296e156e3))
* **ocaml:** seal lexical loop control targets ([a807af2](https://github.com/fullofcaffeine/hxhx/commit/a807af23be83da01d2e9e3804926272088c6d861))
* **ocaml:** seal nullable Bool call crossings ([b44c424](https://github.com/fullofcaffeine/hxhx/commit/b44c4246e86ba0ade09278c2c4a6be89b8e42a92))
* **ocaml:** seal nullable Int Bytes arguments ([577bfd4](https://github.com/fullofcaffeine/hxhx/commit/577bfd45e7a9ceeb7721f852069a4a6759b81f7f))
* **ocaml:** seal nullable Int call crossings ([17b2fe5](https://github.com/fullofcaffeine/hxhx/commit/17b2fe551a1614901e31586119d91a488565c20c))
* **ocaml:** seal optional String calls ([6e6bd47](https://github.com/fullofcaffeine/hxhx/commit/6e6bd47e21659ba14081097c57f15ce60cc4c17d))
* **ocaml:** seal ordinary anonymous structures ([20f7352](https://github.com/fullofcaffeine/hxhx/commit/20f7352a18634830726ac24656da6bb5a9a7994c))
* **ocaml:** seal standard IMap calls before syntax ([e63dadf](https://github.com/fullofcaffeine/hxhx/commit/e63dadf1ffb68b3d3951b2ca23df019086fc57d1))
* **ocaml:** seal trailing optional primitive calls ([b856323](https://github.com/fullofcaffeine/hxhx/commit/b8563238b3798aede3e1f1a2d4b4c43d6e1dbec2))
* **ocaml:** seal two-argument call order ([84a0e45](https://github.com/fullofcaffeine/hxhx/commit/84a0e45e0b438ae9c2f7b958ca0c33c9eae90d7e))
* **ocaml:** seal typed Float catches ([43ed17c](https://github.com/fullofcaffeine/hxhx/commit/43ed17c129a32eb27a364723cb64048b74dbf133))
* **ocaml:** seal zero-argument static calls ([f591f80](https://github.com/fullofcaffeine/hxhx/commit/f591f800fdafdb1eab16ffb887ab2706d3c336c1))
* **ocaml:** shadow replay packed source ([c9c9fb0](https://github.com/fullofcaffeine/hxhx/commit/c9c9fb0e950fd2a5f18bb2db918198cf7ff3aa66))
* **perf:** add safe compiler-scale Reflaxe profiling ([819022e](https://github.com/fullofcaffeine/hxhx/commit/819022e55e76ddb055363387f23b75a33247d693))
* **reflaxe-ocaml:** authorize boolean call boxing ([9de7fc0](https://github.com/fullofcaffeine/hxhx/commit/9de7fc0fd758af60d3fcfb6c4bff5c947356ea04))
* **reflaxe-ocaml:** authorize direct String method uses ([15d2748](https://github.com/fullofcaffeine/hxhx/commit/15d274893a6de7d0ccc9f1646d540137773389af))
* **reflaxe-ocaml:** authorize fromCharCode runtime use ([209b9d8](https://github.com/fullofcaffeine/hxhx/commit/209b9d871dbc8c55c8acee4dc89d12a8d5574097))
* **reflaxe-ocaml:** authorize nullable field defaults ([bdf16e6](https://github.com/fullofcaffeine/hxhx/commit/bdf16e69b3d47859fc910bf7c31c4b4889e4a28e))
* **reflaxe-ocaml:** authorize planned catch runtime uses ([4a0e72c](https://github.com/fullofcaffeine/hxhx/commit/4a0e72cc2a6ea6c5b8ea894838808499431d3ca2))
* **reflaxe-ocaml:** authorize static string runtime uses ([ab094de](https://github.com/fullofcaffeine/hxhx/commit/ab094def9b6886ff7d23e72388afb227390fe31c))
* **reflaxe-ocaml:** authorize String comparator null checks ([aa11f24](https://github.com/fullofcaffeine/hxhx/commit/aa11f24c0cd05bf6c9a8a54dabfc28ad2f05a371))
* **reflaxe-ocaml:** authorize String equality runtime use ([5312ada](https://github.com/fullofcaffeine/hxhx/commit/5312adaa8c61cd18a59f9948e3f833f97efcdf4d))
* **reflaxe-ocaml:** authorize String length reads ([96d1d7f](https://github.com/fullofcaffeine/hxhx/commit/96d1d7f727d7c68965712071aeec82f0ad65975f))
* **reflaxe-ocaml:** authorize throw payload helpers ([a104cf9](https://github.com/fullofcaffeine/hxhx/commit/a104cf950f0bdd3f90094159f0b0be05281db877))
* **reflaxe-ocaml:** expose integer unary authority ([0e0ad96](https://github.com/fullofcaffeine/hxhx/commit/0e0ad9637bb446b897331c02701f51d9f3c55a04))
* **reflaxe-ocaml:** identify zero-argument closures ([672989a](https://github.com/fullofcaffeine/hxhx/commit/672989a67a46b54d0b5be09b5e22d8f5f6f35d8c))
* **reflaxe-ocaml:** plan exact integer unary helpers ([25cf761](https://github.com/fullofcaffeine/hxhx/commit/25cf7617fdc02f40527a112841b3f74eebe1eb85))
* **reflaxe-ocaml:** plan fromCharCode runtime use ([4854e11](https://github.com/fullofcaffeine/hxhx/commit/4854e1175e4540b60801bdeed6de83de51a2c758))
* **reflaxe-ocaml:** preserve Dynamic return carriers ([a434150](https://github.com/fullofcaffeine/hxhx/commit/a434150974bcbe1d26db34435c863e37993ca29b))
* **reflaxe-ocaml:** preserve nullable early-return carriers ([1a5994d](https://github.com/fullofcaffeine/hxhx/commit/1a5994d65d8cffcde8229f731ee58cf204b1863b))
* **reflaxe-ocaml:** seal all return boundaries ([b834a8c](https://github.com/fullofcaffeine/hxhx/commit/b834a8c18e4d488bf6911b0be49d5ccc088590c8))
* **reflaxe-ocaml:** seal call-produced optional callbacks ([c7ba457](https://github.com/fullofcaffeine/hxhx/commit/c7ba4574d94ef700b0302647348b8e2a766cc34a))
* **reflaxe-ocaml:** seal callback signature matrix ([d980dc1](https://github.com/fullofcaffeine/hxhx/commit/d980dc192cdc3969a2f07b63d7ed2957ae9f718f))
* **reflaxe-ocaml:** seal effect-only Void calls ([cd36150](https://github.com/fullofcaffeine/hxhx/commit/cd361504065089102ec1e249a1b7a2bf96852269))
* **reflaxe-ocaml:** seal exact Bool field storage ([9216ed5](https://github.com/fullofcaffeine/hxhx/commit/9216ed5c43750682caa24b62ffec07eba8cfc382))
* **reflaxe-ocaml:** seal exact Bool local carriers ([59a677f](https://github.com/fullofcaffeine/hxhx/commit/59a677f23ff1da8c0f46e7ef7109cde030b2c099))
* **reflaxe-ocaml:** seal exact Int field defaults ([d6603fc](https://github.com/fullofcaffeine/hxhx/commit/d6603fc5b73235e2579485164662e65910f9990d))
* **reflaxe-ocaml:** seal exact Int function-value calls ([7d44564](https://github.com/fullofcaffeine/hxhx/commit/7d445647dc0029913d2b3d9e5336daa49cc4c16e))
* **reflaxe-ocaml:** seal instance Int results ([9de8f92](https://github.com/fullofcaffeine/hxhx/commit/9de8f9204d57075fc2e1fadff30f073462c08438))
* **reflaxe-ocaml:** seal instance receiver order ([e127d22](https://github.com/fullofcaffeine/hxhx/commit/e127d2263f520698a70fa8354b3c113fc05be366))
* **reflaxe-ocaml:** seal instance String results ([0639cb3](https://github.com/fullofcaffeine/hxhx/commit/0639cb38eadfd8a6e546479bf467cf2930dc4296))
* **reflaxe-ocaml:** seal instance Void results ([f10e663](https://github.com/fullofcaffeine/hxhx/commit/f10e6639bcc5169f2a8a27ce36edaa3c61513bb1))
* **reflaxe-ocaml:** seal monomorphic class carriers ([19d926f](https://github.com/fullofcaffeine/hxhx/commit/19d926f7edfb8070f1745913fcd233fcebde9663))
* **reflaxe-ocaml:** seal nested exception control ([03500b3](https://github.com/fullofcaffeine/hxhx/commit/03500b363b280acd7987be7cb46e9463b48d6b30))
* **reflaxe-ocaml:** seal nested int return plans ([3de9efa](https://github.com/fullofcaffeine/hxhx/commit/3de9efa5a30550c4e60d58586c1ec3f1eed03908))
* **reflaxe-ocaml:** seal Null<Bool> local truthiness ([55e4ede](https://github.com/fullofcaffeine/hxhx/commit/55e4ede5ce0df1ae684db82a664a6f05f9d21679))
* **reflaxe-ocaml:** seal Null<Int> local conversions ([bbd0840](https://github.com/fullofcaffeine/hxhx/commit/bbd0840c013afce495f4cec251cd5a60862bb2ed))
* **reflaxe-ocaml:** seal nullable primitive field defaults ([1399257](https://github.com/fullofcaffeine/hxhx/commit/139925758476038cd6e963b7d6cc51ff9181e403))
* **reflaxe-ocaml:** seal optional String function calls ([e748a30](https://github.com/fullofcaffeine/hxhx/commit/e748a3012100c21d7df5837953b536bf99567d77))
* **reflaxe-ocaml:** seal payloadless Void returns ([af6f177](https://github.com/fullofcaffeine/hxhx/commit/af6f177a619b11c0a0c68d69ef8c793c45f880ad))
* **reflaxe-ocaml:** seal represented nested returns ([40a5777](https://github.com/fullofcaffeine/hxhx/commit/40a5777ddd5d5dea728b27868368e733025de0f8))
* **reflaxe-ocaml:** seal runtime type checks ([42f2f0b](https://github.com/fullofcaffeine/hxhx/commit/42f2f0b37c922405f783b1091c6d78bc6687849e))
* **reflaxe-ocaml:** seal structural iterator calls ([5057431](https://github.com/fullofcaffeine/hxhx/commit/505743197746a9b75664d9b5a348b67860ac9ed4))
* **reflaxe-ocaml:** separate function result ownership ([9dff597](https://github.com/fullofcaffeine/hxhx/commit/9dff59763c3fa146ac95785f075347688e65950d))
* **reflaxe-ocaml:** type structural field overlaps ([8a59fe6](https://github.com/fullofcaffeine/hxhx/commit/8a59fe6306cdd9c6cd312f7877250aa5328a1d6d))
* **reflaxe.ocaml:** check nullable Bytes receivers ([01db39d](https://github.com/fullofcaffeine/hxhx/commit/01db39d303a61abec77c5b25d9ddf5a7881cd5f8))
* **reflaxe.ocaml:** explain String runtime sentinel ([d8e76f0](https://github.com/fullofcaffeine/hxhx/commit/d8e76f05bcf43946bf4f83232749716840be9e98))
* **reflaxe.ocaml:** preserve explicit Bytes length ([9f509e2](https://github.com/fullofcaffeine/hxhx/commit/9f509e26fb26ef5d10e0eff272efa6135a87db31))
* **reflaxe.ocaml:** seal Bytes producer plans ([66ac6c2](https://github.com/fullofcaffeine/hxhx/commit/66ac6c27b7d8d8d95621d3e5df70930d8182e547))
* **reflaxe.ocaml:** seal callable result conversions ([5e44a50](https://github.com/fullofcaffeine/hxhx/commit/5e44a5020293c3f1bf6d86137c78e1f07ba2db03))
* **reflaxe.ocaml:** seal Dynamic throw transport ([906405e](https://github.com/fullofcaffeine/hxhx/commit/906405e5f5d7a3064b09610d130a1405e336bbfb))
* **reflaxe.ocaml:** seal exact Bytes accesses ([69bd7ef](https://github.com/fullofcaffeine/hxhx/commit/69bd7ef02d613e98000652e9a5639ce18167eeae))
* **reflaxe.ocaml:** seal exact Bytes mutations ([bdc21f3](https://github.com/fullofcaffeine/hxhx/commit/bdc21f3013a08048b468d172fc70b55d5d634ce9))
* **reflaxe.ocaml:** seal exact Bytes reads ([fc66bd2](https://github.com/fullofcaffeine/hxhx/commit/fc66bd2877262c2e8227918ee670e8a42e030842))
* **reflaxe.ocaml:** seal Haxe exception wrapper catches ([312b2c1](https://github.com/fullofcaffeine/hxhx/commit/312b2c1d36639144194be9978d54fd81d05acc10))
* **reflaxe.ocaml:** seal Haxe exception wrapper throws ([3e08da8](https://github.com/fullofcaffeine/hxhx/commit/3e08da834664a7d9d69a83cbcea36d1db4892c17))
* **reflaxe.ocaml:** seal Int64 Bytes access ([0d06b12](https://github.com/fullofcaffeine/hxhx/commit/0d06b129d31a4985bc9d6b91a9e09e03e64c856b))
* **reflaxe.ocaml:** seal nominal class early returns ([b2d7295](https://github.com/fullofcaffeine/hxhx/commit/b2d72959df37830b5517d7d47e2930dd4133a8ef))
* **reflaxe.ocaml:** seal nominal class exceptions ([10df833](https://github.com/fullofcaffeine/hxhx/commit/10df8338a6ecfaa623578eada9bbbd6824b50c4e))
* **reflaxe.ocaml:** seal nullable early conversions ([b08f2ff](https://github.com/fullofcaffeine/hxhx/commit/b08f2ffbf0bd12d4e93479b34ce2acfac95b8344))
* **reflaxe.ocaml:** seal nullable primitive throws ([e3bae3b](https://github.com/fullofcaffeine/hxhx/commit/e3bae3b232f3969e07ffc95c143dd530abda6528))
* **reflaxe.ocaml:** seal numeric Bytes access ([d8c68d4](https://github.com/fullofcaffeine/hxhx/commit/d8c68d408e80ebfc2b65f33246cddd53c9767a84))
* **reflaxe.ocaml:** seal the Bytes carrier contract ([bef39c2](https://github.com/fullofcaffeine/hxhx/commit/bef39c2342632689eb684bc83a29330fdb90bd77))
* **reflaxe:** add explicit local server authoring mode ([88ad0e6](https://github.com/fullofcaffeine/hxhx/commit/88ad0e63c6b344349e880286c27b5811f652d6e8))
* **reflaxe:** preserve Dune state across source publication ([0d4761b](https://github.com/fullofcaffeine/hxhx/commit/0d4761b98c24b9fce840ddae19b09edaaf27f948))
* **reflaxe:** probe target reuse before preparation ([16b1b79](https://github.com/fullofcaffeine/hxhx/commit/16b1b79febadc0f6eb5733f536e8d4dd9c4388f2))
* **reflaxe:** prove reusable target catalog realm ([257833e](https://github.com/fullofcaffeine/hxhx/commit/257833e2157842b0f7efae48eb3045239e22fc52))
* **reflaxe:** report exact target reuse observations ([5d77ee8](https://github.com/fullofcaffeine/hxhx/commit/5d77ee811b6addc24c3e5ec4abc304937cdd42cc))
* **reflaxe:** support warm server routing ([0471817](https://github.com/fullofcaffeine/hxhx/commit/0471817f4a7c9bc5a13563f013147ab439aa9417))
* **runtime:** authorize first array store occurrence ([07f0902](https://github.com/fullofcaffeine/hxhx/commit/07f09022cce234033f8e15ed9b1e3b15ad2b73a1))
* **runtime:** check dynamic stringifier uses ([3bab1bb](https://github.com/fullofcaffeine/hxhx/commit/3bab1bb52e04d2dd9b4fc52cf0c192c569cc638f))
* **runtime:** check generated plugin text ([0ee3fab](https://github.com/fullofcaffeine/hxhx/commit/0ee3fabbe99019629109e6cd396e22ac24387c56))
* **runtime:** check reflection constructor uses ([d26f9b1](https://github.com/fullofcaffeine/hxhx/commit/d26f9b1d65da91087129a7b6cdacb40730c34adc))
* **runtime:** check type registry metadata ([654aade](https://github.com/fullofcaffeine/hxhx/commit/654aadeb906759cd0afb05367f345ab665b8725f))
* **server:** add compiler-scale Reflaxe proof ([35aec28](https://github.com/fullofcaffeine/hxhx/commit/35aec28992e9a9b3afd9642e0302360f3222d96b))


### Performance Improvements

* **reflaxe-ocaml:** bound runtime authority checks ([f01f858](https://github.com/fullofcaffeine/hxhx/commit/f01f858e45b22eba3ac0fa253f21e6227f937009))
* **reflaxe:** adopt streamed body fingerprints ([a87a957](https://github.com/fullofcaffeine/hxhx/commit/a87a957e0eacda36a3425053adf113765dd98aff))
* **reflaxe:** measure class preparation separately ([7aec7f6](https://github.com/fullofcaffeine/hxhx/commit/7aec7f674534bae4b69b405c1ec1487cd9973d0f))
* **reflaxe:** observe each body once before syntax ([0978038](https://github.com/fullofcaffeine/hxhx/commit/097803880838ff640b3753196a26977d0ac78eac))

## [0.33.4](https://github.com/fullofcaffeine/hxhx/compare/v0.33.3...v0.33.4) (2026-07-23)


### Bug Fixes

* **tooling:** bound bootstrap process discovery ([910320f](https://github.com/fullofcaffeine/hxhx/commit/910320fd0d8b1f0ad59905b9f4e80f3150f30d12))

## [0.33.3](https://github.com/fullofcaffeine/hxhx/compare/v0.33.2...v0.33.3) (2026-07-23)


### Bug Fixes

* **tooling:** distinguish bootstrap stalls from slow work ([e653cea](https://github.com/fullofcaffeine/hxhx/commit/e653ceacf0dff0bb89dbacfff7d7b96341cf889c))

## [0.33.2](https://github.com/fullofcaffeine/hxhx/compare/v0.33.1...v0.33.2) (2026-07-23)


### Bug Fixes

* **hxhx:** load inherited types during native typing ([35df14f](https://github.com/fullofcaffeine/hxhx/commit/35df14fb1e67fb7d3ee6f60dcd971b51e78cd376))
* **hxhx:** preserve module directive meaning ([e64e074](https://github.com/fullofcaffeine/hxhx/commit/e64e0745983d67174fa8fe0a353d85d3a9214a47))
* **hxhx:** reject private static imports ([3206814](https://github.com/fullofcaffeine/hxhx/commit/32068146346e15ef7b77cceb9362394630118155))

## [0.33.1](https://github.com/fullofcaffeine/hxhx/compare/v0.33.0...v0.33.1) (2026-07-23)


### Bug Fixes

* **hxhx:** prepare lazy build-macro modules before typing ([75a5f95](https://github.com/fullofcaffeine/hxhx/commit/75a5f955d3363a65cee62985330068e52b65ba8e))

# [0.33.0](https://github.com/fullofcaffeine/hxhx/compare/v0.32.0...v0.33.0) (2026-07-23)


### Features

* **hxhx:** observe build macro declarations ([1a9441f](https://github.com/fullofcaffeine/hxhx/commit/1a9441f60632fcd4ae24e373dc3ff8600a5c26c6))

# [0.32.0](https://github.com/fullofcaffeine/hxhx/compare/v0.31.0...v0.32.0) (2026-07-23)


### Features

* **hxhx:** observe conditional compilation inputs ([4206911](https://github.com/fullofcaffeine/hxhx/commit/4206911172190c988df982a0af61f403c32133f9))

# [0.31.0](https://github.com/fullofcaffeine/hxhx/compare/v0.30.0...v0.31.0) (2026-07-23)


### Features

* **hxhx:** track typed module source origins ([2118f86](https://github.com/fullofcaffeine/hxhx/commit/2118f86d77010703d58b754a6b587583f7fb8438))

# [0.30.0](https://github.com/fullofcaffeine/hxhx/compare/v0.29.0...v0.30.0) (2026-07-22)


### Features

* **hxhx:** observe embedded constant dependencies ([c3f99d1](https://github.com/fullofcaffeine/hxhx/commit/c3f99d138a65d190ce82d9b4546cfd4c543270a9))

# [0.29.0](https://github.com/fullofcaffeine/hxhx/compare/v0.28.0...v0.29.0) (2026-07-22)


### Features

* **hxhx:** observe initial typed module dependencies ([eb023c4](https://github.com/fullofcaffeine/hxhx/commit/eb023c45e29750f5f8ea00aa32f721705a38a687))

# [0.28.0](https://github.com/fullofcaffeine/hxhx/compare/v0.27.0...v0.28.0) (2026-07-22)


### Features

* **hxhx:** cache source and parser work in native server ([86fc570](https://github.com/fullofcaffeine/hxhx/commit/86fc570d8fdbc37bc680fdf8562a786dc797a818))

# [0.27.0](https://github.com/fullofcaffeine/hxhx/compare/v0.26.0...v0.27.0) (2026-07-22)


### Features

* **hxhx:** seal cache-free server request state ([58a99b2](https://github.com/fullofcaffeine/hxhx/commit/58a99b2d70d0a52466e83e62210166753788d637))

# [0.26.0](https://github.com/fullofcaffeine/hxhx/compare/v0.25.0...v0.26.0) (2026-07-22)


### Features

* **server:** publish output only after request success ([2daa775](https://github.com/fullofcaffeine/hxhx/commit/2daa775eec488f24361c5f201f8e517f4331b952))

# [0.25.0](https://github.com/fullofcaffeine/hxhx/compare/v0.24.0...v0.25.0) (2026-07-22)


### Features

* **server:** add cooperative request deadlines ([e7f09fb](https://github.com/fullofcaffeine/hxhx/commit/e7f09fbde7d36515eab447398b5f82403612eaa6))

# [0.24.0](https://github.com/fullofcaffeine/hxhx/compare/v0.23.18...v0.24.0) (2026-07-22)


### Features

* **server:** add acknowledged native shutdown ([4324f39](https://github.com/fullofcaffeine/hxhx/commit/4324f391f1de32ca5e7025006f7d368c7894e56e))

## [0.23.18](https://github.com/fullofcaffeine/hxhx/compare/v0.23.17...v0.23.18) (2026-07-22)


### Bug Fixes

* **server:** bound native request frames ([43b6d2b](https://github.com/fullofcaffeine/hxhx/commit/43b6d2bfac9906d4d417827b47c5ab10db7a6b0e))

## [0.23.17](https://github.com/fullofcaffeine/hxhx/compare/v0.23.16...v0.23.17) (2026-07-22)


### Bug Fixes

* **server:** clean state after each native request ([551f25b](https://github.com/fullofcaffeine/hxhx/commit/551f25b8ac15e05b6145c27a03fba602944d3c1e))

## [0.23.16](https://github.com/fullofcaffeine/hxhx/compare/v0.23.15...v0.23.16) (2026-07-22)


### Bug Fixes

* **server:** return compiler output to requesting clients ([38941de](https://github.com/fullofcaffeine/hxhx/commit/38941debbe9c48635782759bae2aa025a7027e7d))

## [0.23.15](https://github.com/fullofcaffeine/hxhx/compare/v0.23.14...v0.23.15) (2026-07-22)


### Bug Fixes

* **server:** unify native request dispatch ([9ab332f](https://github.com/fullofcaffeine/hxhx/commit/9ab332f6c7e9ff6f52480e6e7c59e45001b7b53a))

## [0.23.14](https://github.com/fullofcaffeine/hxhx/compare/v0.23.13...v0.23.14) (2026-07-22)


### Bug Fixes

* **tooling:** block incomplete warm Reflaxe builds ([6ee781e](https://github.com/fullofcaffeine/hxhx/commit/6ee781e3b221b3e33b99937f6c8ffc641daec451))

## [0.23.13](https://github.com/fullofcaffeine/hxhx/compare/v0.23.12...v0.23.13) (2026-07-22)


### Bug Fixes

* **tooling:** monitor the real Haxe server worker ([e96e5be](https://github.com/fullofcaffeine/hxhx/commit/e96e5be5ad15da48421e5f570e1d986a253d0197))

## [0.23.12](https://github.com/fullofcaffeine/hxhx/compare/v0.23.11...v0.23.12) (2026-07-22)


### Bug Fixes

* **ast:** keep macro declarations in one recursive type ([bd2ca56](https://github.com/fullofcaffeine/hxhx/commit/bd2ca56829caa53ac2af5eceaa4f647079e158a0))
* **codegen:** avoid helper constructor collision ([5df842a](https://github.com/fullofcaffeine/hxhx/commit/5df842a208e9c14bc6a5434d4d425e4e5de03d79))
* **macros:** traverse return expression values ([a19f264](https://github.com/fullofcaffeine/hxhx/commit/a19f264fca0c74975cbcc291a98ac9e05d3e055e))
* **parser:** preserve local declaration metadata ([fd2cd24](https://github.com/fullofcaffeine/hxhx/commit/fd2cd240460aa86262042bc3f38a483aac567739))
* **parser:** preserve macro variable declarations ([d49a73f](https://github.com/fullofcaffeine/hxhx/commit/d49a73f22bc90341a7b6a9a115d2b70ac85d2986))
* **parser:** preserve return macro arguments ([c2169a5](https://github.com/fullofcaffeine/hxhx/commit/c2169a52ed483741d4756842102d87c2fe285886))
* **parser:** preserve while syntax passed to macros ([7179eb9](https://github.com/fullofcaffeine/hxhx/commit/7179eb92012ffa543d9facc0456c2929c7127c65))
* **typer:** bind nullable abstract conversions ([413d58f](https://github.com/fullofcaffeine/hxhx/commit/413d58f8dcddd5b57e6f1f311d3d2489d1335183))
* **typer:** preserve nested loop control ([a17629e](https://github.com/fullofcaffeine/hxhx/commit/a17629ea85ba87a35ffa95ac7bf96d6e75a2a023))

## [0.23.11](https://github.com/fullofcaffeine/hxhx/compare/v0.23.10...v0.23.11) (2026-07-21)


### Bug Fixes

* **ci:** accept verified manual Gate 1 runs ([b313854](https://github.com/fullofcaffeine/hxhx/commit/b31385403ce56fdf6268ecc1413fbd741c0cdaa1))

## [0.23.10](https://github.com/fullofcaffeine/hxhx/compare/v0.23.9...v0.23.10) (2026-07-21)


### Bug Fixes

* **ci:** resolve the closed Gate 1 incident ([083d49b](https://github.com/fullofcaffeine/hxhx/commit/083d49b177742d9f4c728e71b162dd683d007132))

## [0.23.9](https://github.com/fullofcaffeine/hxhx/compare/v0.23.8...v0.23.9) (2026-07-21)


### Bug Fixes

* **ci:** resolve the closed Gate 1 incident ([360f083](https://github.com/fullofcaffeine/hxhx/commit/360f0833f45fb1e807d882985d5dfb4d934c7687))
* **stage3:** convert Int values stored in Int64 locals ([120f2f3](https://github.com/fullofcaffeine/hxhx/commit/120f2f3f1bd15341ede4711948387fc0c30e46cd))
* **stage3:** convert Int64 call arguments ([7c1ee9e](https://github.com/fullofcaffeine/hxhx/commit/7c1ee9e1d787a83ed095fa3ec7d498333f932b5a))
* **stage3:** cross the erased signature boundary explicitly ([816f122](https://github.com/fullofcaffeine/hxhx/commit/816f122cf510098bee98a1e3dece26ff7d9c29ca))
* **stage3:** emit Int64 local updates ([b9307db](https://github.com/fullofcaffeine/hxhx/commit/b9307db0851bc73454d9a0894cfdb2d93af32dea))
* **stage3:** infer qualified Int64 locals ([2878e71](https://github.com/fullofcaffeine/hxhx/commit/2878e71aa04ad3f1c443a55d401d5fa885727574))
* **stage3:** preserve erased signature map lookup ([e20ed77](https://github.com/fullofcaffeine/hxhx/commit/e20ed772b8d435d29b8c0b39011b1e883b24e39a))
* **stage3:** retain signatures from wildcard imports ([5012da7](https://github.com/fullofcaffeine/hxhx/commit/5012da7dfe66e6eef7a05fa96baf6c96a0ac8c60))
* **stage3:** unpack the native signature map once ([a0198cc](https://github.com/fullofcaffeine/hxhx/commit/a0198cc05b8e255936bb287c5888901705e662d5))
* **stage3:** use typed call signature lookup ([ca66022](https://github.com/fullofcaffeine/hxhx/commit/ca66022f5fc1c1f15b298c0d408b0bf79c2cd640))

## [0.23.8](https://github.com/fullofcaffeine/hxhx/compare/v0.23.7...v0.23.8) (2026-07-21)


### Bug Fixes

* **stage3:** limit native lambda type fallback ([59f7c5d](https://github.com/fullofcaffeine/hxhx/commit/59f7c5d7a5f32e844613da3c736e12cad11b3f79))

## [0.23.7](https://github.com/fullofcaffeine/hxhx/compare/v0.23.6...v0.23.7) (2026-07-21)


### Bug Fixes

* **bootstrap:** align server with selected Haxe ([5503f89](https://github.com/fullofcaffeine/hxhx/commit/5503f891bd5a2d223a16d68b61bcc97e8a4ae180))
* **bootstrap:** exclude local report receipts ([743ef98](https://github.com/fullofcaffeine/hxhx/commit/743ef98434dcb3a2592acdf0476fe99d8864d016))
* **stage3:** keep intrinsic dispatch typed ([cdb41c5](https://github.com/fullofcaffeine/hxhx/commit/cdb41c52ec5a6fbbfb3b124da37fbdeae5a0028a))
* **stage3:** preserve native temporary type scopes ([d56cda7](https://github.com/fullofcaffeine/hxhx/commit/d56cda70c5a4a47d3aa47361466af2ae97fc8d7f))
* **stage3:** scope generated lambda names explicitly ([7dcdee3](https://github.com/fullofcaffeine/hxhx/commit/7dcdee3dc65d1367a929aeb72e9704a9d0681a94))

## [0.23.6](https://github.com/fullofcaffeine/hxhx/compare/v0.23.5...v0.23.6) (2026-07-21)


### Bug Fixes

* **stage3:** provide selected Int64 helpers ([23c1444](https://github.com/fullofcaffeine/hxhx/commit/23c1444efd05c030e6557662881761caa7c11346))

## [0.23.5](https://github.com/fullofcaffeine/hxhx/compare/v0.23.4...v0.23.5) (2026-07-21)


### Bug Fixes

* **ocaml:** make large AST scans stack-safe ([4f9a6d3](https://github.com/fullofcaffeine/hxhx/commit/4f9a6d32d8a431196c0fee6ffd08dca97f975a9b))
* **ocaml:** plan mutable static storage before emission ([0a6036c](https://github.com/fullofcaffeine/hxhx/commit/0a6036cc463552437f8967232df3c9df102a822d))
* **ocaml:** reject impossible static carrier order ([fede760](https://github.com/fullofcaffeine/hxhx/commit/fede7609100e6b2c1fc3a990fe0ee8658db0e97d))
* **ocaml:** validate static initializer dependencies ([e018290](https://github.com/fullofcaffeine/hxhx/commit/e018290705493fc516b02fc09dd7f4159bbdd313))
* **parser:** preserve null-safe field access ([adae08d](https://github.com/fullofcaffeine/hxhx/commit/adae08d88eeff6223a391e66e4f8e88d9b0feb37))
* **tooling:** quiet repeated heavy-run waits ([9a5bd94](https://github.com/fullofcaffeine/hxhx/commit/9a5bd94c34bb902173e1a2da6cfe876a0aa1ae3b))

## [0.23.4](https://github.com/fullofcaffeine/hxhx/compare/v0.23.3...v0.23.4) (2026-07-21)


### Bug Fixes

* **tooling:** warn on oversized Beads history ([f200964](https://github.com/fullofcaffeine/hxhx/commit/f20096441ced9edc9fde9bfcb51942a94ae9785a))

## [0.23.3](https://github.com/fullofcaffeine/hxhx/compare/v0.23.2...v0.23.3) (2026-07-20)


### Bug Fixes

* **tooling:** recover cleanup under low disk space ([b020806](https://github.com/fullofcaffeine/hxhx/commit/b020806143f07266235a42dfca39cb5880a61814))
* **tooling:** warn on byte-heavy Git objects ([c81eb5e](https://github.com/fullofcaffeine/hxhx/commit/c81eb5eed54e9ba895235aaf6fad19f5099bf92a))

## [0.23.2](https://github.com/fullofcaffeine/hxhx/compare/v0.23.1...v0.23.2) (2026-07-20)


### Bug Fixes

* **ci:** retain unreleased QA risk ([60638d1](https://github.com/fullofcaffeine/hxhx/commit/60638d128471fcdceadcc06ca98e8aeede423903))
* **release:** verify exact Core QA proof ([76b8ebd](https://github.com/fullofcaffeine/hxhx/commit/76b8ebd27989702b9bc0380c4cc1878ab2894352))

## [0.23.1](https://github.com/fullofcaffeine/hxhx/compare/v0.23.0...v0.23.1) (2026-07-20)


### Bug Fixes

* **ocaml:** distinguish program modules from runtime ([88b767e](https://github.com/fullofcaffeine/hxhx/commit/88b767eb568c5aa2f18a53cf0ec3a097153cde46))
* **tooling:** isolate macro-host build state ([2c10446](https://github.com/fullofcaffeine/hxhx/commit/2c10446d6b7fdda3cab479beeb7ae3c1b5b8e1c1))

# [0.23.0](https://github.com/fullofcaffeine/hxhx/compare/v0.22.0...v0.23.0) (2026-07-20)


### Bug Fixes

* **ocaml:** avoid overstating runtime evidence ([872e073](https://github.com/fullofcaffeine/hxhx/commit/872e0731b26f874ab7b2d8eb0e5e9539ff58d884))
* **ocaml:** preserve nested local rebinding ([ede7a3c](https://github.com/fullofcaffeine/hxhx/commit/ede7a3c3624f07189cccacdaa6223528ffed6e1a))
* **tooling:** bound heavy formatter work ([5eb905f](https://github.com/fullofcaffeine/hxhx/commit/5eb905f7dd3236e2d3f1c3b1fe16132139771548))
* **tooling:** ignore deleted Haxe format paths ([d6a59c2](https://github.com/fullofcaffeine/hxhx/commit/d6a59c26e1630b0956bfad07c591dafe45515bd4))


### Features

* **ocaml:** centralize exact Int representation ([df8540e](https://github.com/fullofcaffeine/hxhx/commit/df8540e00e6016707412dff624f333bb42b4effe))
* **ocaml:** declare native runtime needs ([ab76142](https://github.com/fullofcaffeine/hxhx/commit/ab761426ac29d2cbeb5f63902acbbcbca130fd28))
* **ocaml:** explain compiler runtime support ([40fe524](https://github.com/fullofcaffeine/hxhx/commit/40fe52417b1ceb2b95b015f0a987fadd77976777))
* **ocaml:** explain float bit runtime needs ([68edee8](https://github.com/fullofcaffeine/hxhx/commit/68edee8460ae6d781d26be799b97d65b7ae627f2))
* **ocaml:** explain place runtime requirements ([98ad4cd](https://github.com/fullofcaffeine/hxhx/commit/98ad4cdbb0a833862e7affa20b79ed7b656439e6))
* **ocaml:** inventory generated artifacts ([c501d3f](https://github.com/fullofcaffeine/hxhx/commit/c501d3fd030c53424176deef123d94c619ee8262))
* **ocaml:** lock runtime source catalog ([c550da5](https://github.com/fullofcaffeine/hxhx/commit/c550da51c2b7f60478485645c02a1b0eaff2af2d))
* **ocaml:** trace runtime needs to packaged sources ([558b27b](https://github.com/fullofcaffeine/hxhx/commit/558b27b7b4fef2922739fc7fc51fb7de44caa24a))

# [0.22.0](https://github.com/fullofcaffeine/hxhx/compare/v0.21.5...v0.22.0) (2026-07-20)


### Features

* **ocaml:** define generated artifact ownership ([662fc9a](https://github.com/fullofcaffeine/hxhx/commit/662fc9a5c2e56eb4155850ac15ff4717fa3e8892))

## [0.21.5](https://github.com/fullofcaffeine/hxhx/compare/v0.21.4...v0.21.5) (2026-07-20)


### Performance Improvements

* **deps:** pin faster Reflaxe lifecycle ([b85e928](https://github.com/fullofcaffeine/hxhx/commit/b85e92840a1bb4a8ddd6a84a10de0a7378cee88e)), closes [#10](https://github.com/fullofcaffeine/hxhx/issues/10)
* **ocaml:** reuse one place-plan body binding ([de9846d](https://github.com/fullofcaffeine/hxhx/commit/de9846db7b7a3b416a320fcd42082a5576f5b042))
* **test:** run portable fixtures in bounded pool ([5b6d8a1](https://github.com/fullofcaffeine/hxhx/commit/5b6d8a166d2a0bee8c75d5b68cf9221ac947876c))

## [0.21.4](https://github.com/fullofcaffeine/hxhx/compare/v0.21.3...v0.21.4) (2026-07-20)


### Bug Fixes

* **ocaml:** keep unused defaults warning-clean ([7326225](https://github.com/fullofcaffeine/hxhx/commit/7326225840c69d83d4eb25e4250764a712849ab0))
* **ocaml:** restore exception stack source shape ([025c0dd](https://github.com/fullofcaffeine/hxhx/commit/025c0dd1cd8ecabc48a83e7bd546fb52cb79b1e1))

## [0.21.3](https://github.com/fullofcaffeine/hxhx/compare/v0.21.2...v0.21.3) (2026-07-20)


### Bug Fixes

* **ci:** align the Reflaxe content checksum ([47048af](https://github.com/fullofcaffeine/hxhx/commit/47048afe1591da286ebcf40fcd877e6e1db9839d))
* **ocaml:** seal place plans before emission ([8a80f2f](https://github.com/fullofcaffeine/hxhx/commit/8a80f2fba139eca3337974340d47931c4e2fce75))

## [0.21.2](https://github.com/fullofcaffeine/hxhx/compare/v0.21.1...v0.21.2) (2026-07-20)


### Bug Fixes

* **ocaml:** pin verified Reflaxe framework ([1618943](https://github.com/fullofcaffeine/hxhx/commit/16189437fb18ae4de07f929bd4b875dec61af870))

## [0.21.1](https://github.com/fullofcaffeine/hxhx/compare/v0.21.0...v0.21.1) (2026-07-20)


### Bug Fixes

* **ocaml:** preserve place ownership through preprocessors ([683eaa4](https://github.com/fullofcaffeine/hxhx/commit/683eaa4044dbb40059444fd29ee4908bded43e27))

# [0.21.0](https://github.com/fullofcaffeine/hxhx/compare/v0.20.1...v0.21.0) (2026-07-20)


### Bug Fixes

* **ci:** install findlib for native package proof ([e8f2c0d](https://github.com/fullofcaffeine/hxhx/commit/e8f2c0d7dae5419dfd27377ce779e5871f9c4206))
* **ci:** use portable findlib check ([16e60b5](https://github.com/fullofcaffeine/hxhx/commit/16e60b5a736e827b9986af472441b1d5074710d6))
* **ocaml:** keep exception stack updates owned ([8222339](https://github.com/fullofcaffeine/hxhx/commit/82223398aa40b17d18f7ca7c3aaa90f92e24d162))
* **ocaml:** keep stack default out of late lowering ([e5457f0](https://github.com/fullofcaffeine/hxhx/commit/e5457f043d81e056f1dad727a33186ff43d1cea0))
* **tooling:** clean test build outputs ([afff192](https://github.com/fullofcaffeine/hxhx/commit/afff192b992f8ad9ed6856542f41d7284a398186))


### Features

* **ci:** classify QA cost by change risk ([de865a7](https://github.com/fullofcaffeine/hxhx/commit/de865a7c15d8202a4f606853f82e58639a7b4b20))
* **ocaml:** add environment doctor ([945a0a2](https://github.com/fullofcaffeine/hxhx/commit/945a0a2896fa8cc2e47b1a375df319d4acce32d8))
* **ocaml:** add runnable project scaffolds ([2503957](https://github.com/fullofcaffeine/hxhx/commit/2503957c7bdb455715cd5c275e1f0bbd2f23e376))
* **ocaml:** add safe build and watch loop ([b8f0afb](https://github.com/fullofcaffeine/hxhx/commit/b8f0afbb3fd66aed56a724f0a4e790a5e58a57fd))
* **ocaml:** inspect compiler-owned output ([6dc2ef9](https://github.com/fullofcaffeine/hxhx/commit/6dc2ef97aec309fe7e251b485a12f57cb1b6da85))
* **ocaml:** measure standalone edit-loop states ([f9b6f87](https://github.com/fullofcaffeine/hxhx/commit/f9b6f879dd4b65a25e374433bfa0cdea5a7fba82))
* **ocaml:** report native build timing ([3a569ae](https://github.com/fullofcaffeine/hxhx/commit/3a569ae653dbda342580f7a6a751e2c0bf6270b0))

## [0.20.1](https://github.com/fullofcaffeine/hxhx/compare/v0.20.0...v0.20.1) (2026-07-19)


### Bug Fixes

* **ci:** keep license notes guard-safe ([3c1648f](https://github.com/fullofcaffeine/hxhx/commit/3c1648f81ae6cbea8cf84f51b923a49d63db6264))
* **ci:** reject partial stage0 profiles ([f688e05](https://github.com/fullofcaffeine/hxhx/commit/f688e0580bcd2c9db785026e1dab30f42e4f1371))

# [0.20.0](https://github.com/fullofcaffeine/hxhx/compare/v0.19.0...v0.20.0) (2026-07-19)


### Bug Fixes

* **ocaml:** preserve typed-place metadata in strings ([e9cdf1f](https://github.com/fullofcaffeine/hxhx/commit/e9cdf1f1272836790c9f37730d54aefc6bc2faf3))
* **tooling:** classify Haxe servers safely ([a8f4437](https://github.com/fullofcaffeine/hxhx/commit/a8f4437fa917180fcab8dd76f3da7a846a2901fc))


### Features

* **ocaml:** lower array updates through typed places ([2ec5fa6](https://github.com/fullofcaffeine/hxhx/commit/2ec5fa62f25b1df441aa1a82f4eb4a9c52e25f76))
* **ocaml:** lower compound field addition through places ([659f37e](https://github.com/fullofcaffeine/hxhx/commit/659f37ec0a0443a790d7d265a3ff00fd9e87aafe))
* **ocaml:** lower field assignments through typed places ([db5f43d](https://github.com/fullofcaffeine/hxhx/commit/db5f43dd393add6703157994e93900e0c428d34f))
* **ocaml:** lower field decrement through typed places ([c841428](https://github.com/fullofcaffeine/hxhx/commit/c841428927d7147ac37ca5e36ee653227b38a072))
* **ocaml:** lower field increment through typed places ([92915b9](https://github.com/fullofcaffeine/hxhx/commit/92915b993cfa1ddbd21e2773ef25f9135a46fe47))
* **ocaml:** lower static addition through typed places ([117e555](https://github.com/fullofcaffeine/hxhx/commit/117e5552f9e3809d0e33af65dba1569a0ef27000))
* **ocaml:** lower static field assignment through typed places ([004f0a8](https://github.com/fullofcaffeine/hxhx/commit/004f0a819d706bdf3693d8075589b0c09ff4faad))
* **ocaml:** lower static updates through typed places ([81054a9](https://github.com/fullofcaffeine/hxhx/commit/81054a9ea3d29c15a4edf98be5907e28508bb0d9))
* **ocaml:** preserve array assignment order ([86d2caa](https://github.com/fullofcaffeine/hxhx/commit/86d2caa2d79d678410330a6ba34408ef44140456))
* **ocaml:** preserve array compound order ([b587c97](https://github.com/fullofcaffeine/hxhx/commit/b587c978b65edb85ef393b9c427a1d2043f411aa))
* **tooling:** block memory-pressured heavy gates ([f2756ac](https://github.com/fullofcaffeine/hxhx/commit/f2756ac9b33d9365b0e25cce586784f8f0418477))
* **tooling:** coordinate queued compiler gates ([41fe774](https://github.com/fullofcaffeine/hxhx/commit/41fe774f4e5cc8f2f6251056dd8d9b154b326510))
* **tooling:** prove cross-repository gate leases ([9f069f2](https://github.com/fullofcaffeine/hxhx/commit/9f069f26feab400ef1aa3e9bec6f8b46a7010e1c))
* **tooling:** queue saturated local gates ([d5c70eb](https://github.com/fullofcaffeine/hxhx/commit/d5c70eb5be7e1889585baf60dd8e7fa732641ccd))


### Performance Improvements

* **ci:** shard core tests across clean runners ([56310df](https://github.com/fullofcaffeine/hxhx/commit/56310df380f5094d9e4eac664ec2f03c5de52c90))
* **tooling:** keep formatter workers busy ([12307bc](https://github.com/fullofcaffeine/hxhx/commit/12307bcdfc11cdb50058ff317643b7b75e4bf381))

# [0.19.0](https://github.com/fullofcaffeine/hxhx/compare/v0.18.19...v0.19.0) (2026-07-18)


### Bug Fixes

* **ci:** ignore package proof OCaml switch ([b9d2acc](https://github.com/fullofcaffeine/hxhx/commit/b9d2acc741631e749232861b568c2461b3ab5b88))
* **ci:** parse mixed haxelib path output ([827efd9](https://github.com/fullofcaffeine/hxhx/commit/827efd913f72969fc78e2d9041f49c2b18155f3b))
* **dev:** track hook state across local commits ([c9bd637](https://github.com/fullofcaffeine/hxhx/commit/c9bd637c960c92be18736828d3c23a27013430db))
* **hxhx:** prevent Haxe server leaks ([4e08299](https://github.com/fullofcaffeine/hxhx/commit/4e08299e98b057de51ca13b26b57cec02acc913d))
* **hxhx:** retain child server ownership ([5c25fab](https://github.com/fullofcaffeine/hxhx/commit/5c25fab890d9e19b77e8e03045b52793bb390d02))


### Features

* **ci:** measure installed package by host ([91fed0f](https://github.com/fullofcaffeine/hxhx/commit/91fed0f8564e9fb5709b30052f14501a0c9a2e33))
* **release:** prove one package across hosts ([20d1bb2](https://github.com/fullofcaffeine/hxhx/commit/20d1bb2a0c39d3af991e57cc1b8cd8e6be06e6c7))


### Performance Improvements

* **dev:** diagnose slow Beads storage ([b818c67](https://github.com/fullofcaffeine/hxhx/commit/b818c6792108affe675e70e2dbee8416b22652e9))
* **dev:** restore safe Git maintenance ([fa70c77](https://github.com/fullofcaffeine/hxhx/commit/fa70c7711bb29a94749911a44a15375772a9a227))
* **dev:** skip redundant Beads checkout imports ([e6d6fd6](https://github.com/fullofcaffeine/hxhx/commit/e6d6fd66811fc7740344895b9b6659942a80930a))
* **hxhx:** extract known C++ signatures ([e2ea897](https://github.com/fullofcaffeine/hxhx/commit/e2ea89749f146431a889cda0e917f660eb06fd92))

## [0.18.19](https://github.com/fullofcaffeine/hxhx/compare/v0.18.18...v0.18.19) (2026-07-18)


### Bug Fixes

* **ci:** locate versioned Neko libraries ([38743e5](https://github.com/fullofcaffeine/hxhx/commit/38743e5f0851a7ce3ca0acefa25f846d8edb03cc))
* **dev:** stabilize profiler artifact paths ([f184a6a](https://github.com/fullofcaffeine/hxhx/commit/f184a6a70a6e344313fe56c1b3b0cdd173604b91))
* **release:** make OCaml package source-only ([3c6f4a0](https://github.com/fullofcaffeine/hxhx/commit/3c6f4a09be84861a4a395b48b6b116799022cae5))


### Performance Improvements

* **cpp:** split generated program prelude ([23c3d38](https://github.com/fullofcaffeine/hxhx/commit/23c3d38f23b2bbc1545dc6f587ffe49d4c78a910))

## [0.18.18](https://github.com/fullofcaffeine/hxhx/compare/v0.18.17...v0.18.18) (2026-07-18)


### Performance Improvements

* **dev:** add isolated fast hxhx builds ([67f3be7](https://github.com/fullofcaffeine/hxhx/commit/67f3be7a54ec98ee63ed4c455c74c8a49aedaec1))
* **dev:** reuse unchanged current-source compilers ([15d5368](https://github.com/fullofcaffeine/hxhx/commit/15d5368649af1924a28e0b8d75087e96d203065d))
* **dev:** stop saturated Gate 3 runs early ([f39f094](https://github.com/fullofcaffeine/hxhx/commit/f39f09491b6fd8fa2faec8a54ddc4b57c785a191))

## [0.18.17](https://github.com/fullofcaffeine/hxhx/compare/v0.18.16...v0.18.17) (2026-07-18)


### Bug Fixes

* **cpp:** preserve inferred IntMap constructors ([b08b454](https://github.com/fullofcaffeine/hxhx/commit/b08b454b502b8332ec21b6f4df2017cd83eea7ea))

## [0.18.16](https://github.com/fullofcaffeine/hxhx/compare/v0.18.15...v0.18.16) (2026-07-18)


### Bug Fixes

* **typer:** contain method generic results ([e9a5f23](https://github.com/fullofcaffeine/hxhx/commit/e9a5f23e64b931c303131ec9c3d2db1bbf7e809e))

## [0.18.15](https://github.com/fullofcaffeine/hxhx/compare/v0.18.14...v0.18.15) (2026-07-17)


### Bug Fixes

* **cpp:** represent callable extern carriers ([f84e564](https://github.com/fullofcaffeine/hxhx/commit/f84e564d89aa4901a362b8f0166b4c97808fee6e))


### Performance Improvements

* **cpp:** skip irrelevant callable lookups ([4465849](https://github.com/fullofcaffeine/hxhx/commit/446584911c9b23cf829c4378533f6bff10f36b28))

## [0.18.14](https://github.com/fullofcaffeine/hxhx/compare/v0.18.13...v0.18.14) (2026-07-17)


### Bug Fixes

* **cpp:** preserve generic Array local carriers ([4a8e820](https://github.com/fullofcaffeine/hxhx/commit/4a8e82092bf8c6ca6d19d0913a58ca7995a46a62))

## [0.18.13](https://github.com/fullofcaffeine/hxhx/compare/v0.18.12...v0.18.13) (2026-07-17)


### Bug Fixes

* **cpp:** lower exact String.indexOf calls ([838d120](https://github.com/fullofcaffeine/hxhx/commit/838d1207c7657a08a9eaa29ab21f109530fea393))

## [0.18.12](https://github.com/fullofcaffeine/hxhx/compare/v0.18.11...v0.18.12) (2026-07-17)


### Bug Fixes

* **cpp:** erase metadata carrier parameters ([8f49897](https://github.com/fullofcaffeine/hxhx/commit/8f49897d880829daded5b020ba99e322ca615e6a))

## [0.18.11](https://github.com/fullofcaffeine/hxhx/compare/v0.18.10...v0.18.11) (2026-07-17)


### Bug Fixes

* **cpp:** preserve Int64 complement ([6206f51](https://github.com/fullofcaffeine/hxhx/commit/6206f516d4409bacc22051eb066aa9c2810c41e0))

## [0.18.10](https://github.com/fullofcaffeine/hxhx/compare/v0.18.9...v0.18.10) (2026-07-17)


### Bug Fixes

* **cpp:** preserve Int modulo Int64 ([9cbd187](https://github.com/fullofcaffeine/hxhx/commit/9cbd187946ec3be59c85f21ba90b98286ac96194))

## [0.18.9](https://github.com/fullofcaffeine/hxhx/compare/v0.18.8...v0.18.9) (2026-07-17)


### Bug Fixes

* **cpp:** preserve Int divided by Int64 ([ca0375a](https://github.com/fullofcaffeine/hxhx/commit/ca0375abdadcdeaf0d014f577c9f75189a9efbd0))

## [0.18.8](https://github.com/fullofcaffeine/hxhx/compare/v0.18.7...v0.18.8) (2026-07-17)


### Bug Fixes

* **cpp:** define Int64 remainder semantics ([4700544](https://github.com/fullofcaffeine/hxhx/commit/47005446f46237624c350ba9aa802979a1987e8f))

## [0.18.7](https://github.com/fullofcaffeine/hxhx/compare/v0.18.6...v0.18.7) (2026-07-17)


### Bug Fixes

* **cpp:** define Int64 division semantics ([cacbbf3](https://github.com/fullofcaffeine/hxhx/commit/cacbbf3a49b2592580a23be9186180d17c3677a2))

## [0.18.6](https://github.com/fullofcaffeine/hxhx/compare/v0.18.5...v0.18.6) (2026-07-17)


### Bug Fixes

* **cpp:** preserve Int64 multiplication wraparound ([638271e](https://github.com/fullofcaffeine/hxhx/commit/638271ea0f805166267218353e0c474af22fa04a))

## [0.18.5](https://github.com/fullofcaffeine/hxhx/compare/v0.18.4...v0.18.5) (2026-07-17)


### Bug Fixes

* **bootstrap:** make no-prepass values explicit ([3ea7211](https://github.com/fullofcaffeine/hxhx/commit/3ea7211a0af07b6bf0dc7b3ef945660236f57b05))
* **typing:** stabilize nullable typed-body projection ([24641f9](https://github.com/fullofcaffeine/hxhx/commit/24641f911eecbbb6f2daf378d3da33b98d0d8f43))

## [0.18.4](https://github.com/fullofcaffeine/hxhx/compare/v0.18.3...v0.18.4) (2026-07-17)


### Bug Fixes

* **cpp:** preserve Int64 intSub operand order ([a1fd552](https://github.com/fullofcaffeine/hxhx/commit/a1fd5523f1d9f3eb226b830e71e883e0c600a69c))

## [0.18.3](https://github.com/fullofcaffeine/hxhx/compare/v0.18.2...v0.18.3) (2026-07-17)


### Bug Fixes

* **cpp:** preserve Int64 subInt wraparound ([f5b54d5](https://github.com/fullofcaffeine/hxhx/commit/f5b54d517203cb0c005bee0c45ae54641d99496d))

## [0.18.2](https://github.com/fullofcaffeine/hxhx/compare/v0.18.1...v0.18.2) (2026-07-17)


### Bug Fixes

* **cpp:** preserve Int64 addInt wraparound ([8378a4a](https://github.com/fullofcaffeine/hxhx/commit/8378a4a632c0f7657f580b6ae199c2da184faf33))

## [0.18.1](https://github.com/fullofcaffeine/hxhx/compare/v0.18.0...v0.18.1) (2026-07-17)


### Bug Fixes

* **cpp:** emit Int64 equality as native comparisons ([43f74b3](https://github.com/fullofcaffeine/hxhx/commit/43f74b37dc93f9a6a3c1e44b25d3a4aa08be4f8f))

# [0.18.0](https://github.com/fullofcaffeine/hxhx/compare/v0.17.0...v0.18.0) (2026-07-16)


### Bug Fixes

* preserve abstract string concatenation ([2145ede](https://github.com/fullofcaffeine/hxhx/commit/2145ede8e96cedb108c367a5e2c25fc5712448f1))
* **typer:** limit abstract operator invariant ([9c3b9df](https://github.com/fullofcaffeine/hxhx/commit/9c3b9df00cca773ebf5156e5813a69875086b4be))
* **typer:** lower bodyless string operators safely ([caa8a82](https://github.com/fullofcaffeine/hxhx/commit/caa8a82b451ed1a2bfd93fc5a2a93d5374729c70))
* **typer:** prefer current fields over type names ([dbe74fb](https://github.com/fullofcaffeine/hxhx/commit/dbe74fbfff7cbc67715bf8a76e67dd308b0c8b36))
* **typer:** preserve local function result types ([281bd92](https://github.com/fullofcaffeine/hxhx/commit/281bd929f508ab9c37b1461ce636d11c79601186))
* **typer:** retain types through computed receivers ([62a0ffa](https://github.com/fullofcaffeine/hxhx/commit/62a0ffafcb7c3e0910e3ca8fe0124d33d53be674))
* **typer:** validate bodyless binary carriers early ([bf7f064](https://github.com/fullofcaffeine/hxhx/commit/bf7f064dca60a642b70f3855e7e6467e976c6732))


### Features

* bind abstract binary operators in shared typing ([38a50fe](https://github.com/fullofcaffeine/hxhx/commit/38a50fe3e39dc8712038780a01587df7dd72f757))

# [0.17.0](https://github.com/fullofcaffeine/hxhx/compare/v0.16.0...v0.17.0) (2026-07-16)


### Bug Fixes

* preserve abstract property update semantics ([21ee3dc](https://github.com/fullofcaffeine/hxhx/commit/21ee3dc8a9857d600705565721d7617e2d0f476f))
* preserve abstract unary semantics through bootstrap ([976730f](https://github.com/fullofcaffeine/hxhx/commit/976730f7707cfc79750513b8f0c4a08220e96090))
* preserve declared method callees in typed bodies ([f6a7e88](https://github.com/fullofcaffeine/hxhx/commit/f6a7e88130d3a70c22d866d86bf1876402c84616))
* preserve returned block expressions ([c134b48](https://github.com/fullofcaffeine/hxhx/commit/c134b48b408c1d2a3e38e92ffc2e604778c04af9))
* refresh typed method lookup bootstrap ([b8f0d9e](https://github.com/fullofcaffeine/hxhx/commit/b8f0d9e5ad881999075891c3a8088b2a22211c84))


### Features

* lower abstract unary operators in shared typer ([c95bb27](https://github.com/fullofcaffeine/hxhx/commit/c95bb2706b99db274d52214f915d3edab07f0f16))
* seal structural typed backend bodies ([8a1fb02](https://github.com/fullofcaffeine/hxhx/commit/8a1fb021982da9a1dc459196ec4b0a25d340b489))

# [0.16.0](https://github.com/fullofcaffeine/hxhx/compare/v0.15.24...v0.16.0) (2026-07-16)


### Features

* index abstract operator declarations ([23fea01](https://github.com/fullofcaffeine/hxhx/commit/23fea0169277d845dcdbca54e703e2b935a6e896))

## [0.15.24](https://github.com/fullofcaffeine/hxhx/compare/v0.15.23...v0.15.24) (2026-07-15)


### Bug Fixes

* preserve unary operator fixity ([bb67b7a](https://github.com/fullofcaffeine/hxhx/commit/bb67b7a42c9820941eabaae21c16c31631a78fa3))

## [0.15.23](https://github.com/fullofcaffeine/hxhx/compare/v0.15.22...v0.15.23) (2026-07-15)


### Bug Fixes

* restore no-prepass stage0 source build ([2abcf34](https://github.com/fullofcaffeine/hxhx/commit/2abcf346f2081701dd89e2756b488c4f1417082d))

## Unreleased

### Changed

* **reflaxe.ocaml:** align the source/package layout with Reflaxe-generated compiler conventions. `reflaxe.ocaml` originally grew in this monorepo without starting from `haxelib run reflaxe new`, so std overrides and haxelib packaging drifted into a bespoke shape. Source overrides now live under `packages/reflaxe.ocaml/std/ocaml/_std`, package metadata lives at `packages/reflaxe.ocaml/haxelib.json`, and release packaging runs Reflaxe's own build flattening so distributable packages get `.cross.hx` overrides from `_std` the same way generated Reflaxe compilers do.

## [0.15.22](https://github.com/fullofcaffeine/hxhx/compare/v0.15.21...v0.15.22) (2026-06-15)


### Bug Fixes

* **php:** dispatch extern inline overloads ([6f336fe](https://github.com/fullofcaffeine/hxhx/commit/6f336feebd0813257489f56e227e16a9cf3a7c39))

## [0.15.21](https://github.com/fullofcaffeine/hxhx/compare/v0.15.20...v0.15.21) (2026-06-15)


### Bug Fixes

* **ci:** pin Lua Gate3 rocks ([1882d8d](https://github.com/fullofcaffeine/hxhx/commit/1882d8d208414992e09c56409d49fc060f113fdd))
* **ci:** pin LuaJIT LuaRocks deps ([a00af6c](https://github.com/fullofcaffeine/hxhx/commit/a00af6c3e2322b10d0703d42f4dc543f58cf07a4))
* **ci:** pin LuaJIT luasec install ([f4bf447](https://github.com/fullofcaffeine/hxhx/commit/f4bf447a29ab4da944bd9b12bbb795327e2bc001))
* **ci:** stop timed-out Gate3 target trees ([d6c41dd](https://github.com/fullofcaffeine/hxhx/commit/d6c41dd10cf47b5d80fa6bac6a43e4e340b24adc))
* **hxhx:** add csharp file copy support ([88bbbd1](https://github.com/fullofcaffeine/hxhx/commit/88bbbd17a8d595912bcd2bfde6c5cd5d5cdb51d0))
* **hxhx:** add csharp map set support surface ([3ddc8f9](https://github.com/fullofcaffeine/hxhx/commit/3ddc8f9cf731931218140c96a3bb6e6b0fc7ea75))
* **hxhx:** add csharp sys default imports ([385b8aa](https://github.com/fullofcaffeine/hxhx/commit/385b8aa897a287b354f7715d010e07521b01e44e))
* **hxhx:** add csharp sys support stubs ([fb43851](https://github.com/fullofcaffeine/hxhx/commit/fb43851c853672248818f262f4b56a1322297952))
* **hxhx:** add focused Lua EReg runtime ([f6dc2cb](https://github.com/fullofcaffeine/hxhx/commit/f6dc2cba8764dc23200f1a9399a3d9f699a71b09))
* **hxhx:** add Lua support prelude ([d3e4750](https://github.com/fullofcaffeine/hxhx/commit/d3e4750f45af19fba339209ca83c56bdf50a428e))
* **hxhx:** add Lua UtilityProcess runtime shim ([118dc4d](https://github.com/fullofcaffeine/hxhx/commit/118dc4d9585a2c9e07cbda034d0972eb10d70acf))
* **hxhx:** advance csharp cstwlibs support ([3651e3c](https://github.com/fullofcaffeine/hxhx/commit/3651e3c3e67673069dbc0349f59a9a9ff45de4fe))
* **hxhx:** align csharp constraint diagnostic spans ([8157eb3](https://github.com/fullofcaffeine/hxhx/commit/8157eb373fba0bd025da8ec316959b3d6fcbc01c))
* **hxhx:** avoid csharp source layout collisions ([4dbb841](https://github.com/fullofcaffeine/hxhx/commit/4dbb84164742da680d946379701d424375727c2e))
* **hxhx:** bind csharp reflect calls statically ([f1074c0](https://github.com/fullofcaffeine/hxhx/commit/f1074c08c8974d7fbc6aa12af3acb89ae44fc842))
* **hxhx:** bind js postfix instance receivers ([bf72c47](https://github.com/fullofcaffeine/hxhx/commit/bf72c47991a9b958513796129f79b1c5577b54a7))
* **hxhx:** bind Lua runci helpers ([f260e8a](https://github.com/fullofcaffeine/hxhx/commit/f260e8a758242d85d285adb5a5dd44985a5f5110))
* **hxhx:** complete csharp raw intrinsic support ([dbcd463](https://github.com/fullofcaffeine/hxhx/commit/dbcd4635713b4347d2677b7fbb5734c3bdfa1bee))
* **hxhx:** dispatch csharp dynamic reflected type calls ([c5954f6](https://github.com/fullofcaffeine/hxhx/commit/c5954f693dd7838f046ab525ac2c00ce6a978b07))
* **hxhx:** emit csharp source support set ([4cbec82](https://github.com/fullofcaffeine/hxhx/commit/4cbec82e777a50e781f4e68a6b5af39b90e1b7b7))
* **hxhx:** emit Lua top-level static helpers ([71df447](https://github.com/fullofcaffeine/hxhx/commit/71df44760fe38e46dbd3f590c08045702940860b))
* **hxhx:** emit only reachable Lua helpers ([f0f7312](https://github.com/fullofcaffeine/hxhx/commit/f0f73121ac06a71a665b638c8c31bcaa159240f3))
* **hxhx:** escape Lua EReg backslash runtime literals ([0b424cf](https://github.com/fullofcaffeine/hxhx/commit/0b424cffcf515dfab3c45596cbb03586fa879994))
* **hxhx:** expose lua type extern ([8b0f76f](https://github.com/fullofcaffeine/hxhx/commit/8b0f76f95f17c3e672707ef24a33db453ddb1dbc))
* **hxhx:** format Lua trace output ([c36118b](https://github.com/fullofcaffeine/hxhx/commit/c36118bdda6d870f5384a8bf15360eb1ce42a0ad))
* **hxhx:** guard csharp support constructor bodies ([bb7ec52](https://github.com/fullofcaffeine/hxhx/commit/bb7ec5240701625d34265d6ca858ca060bf94dcf))
* **hxhx:** handle csharp no-main diagnostics ([0d16a38](https://github.com/fullofcaffeine/hxhx/commit/0d16a380ff8564b995adc727809075ea876acf49))
* **hxhx:** honor csharp no-root namespace ([6bff32d](https://github.com/fullofcaffeine/hxhx/commit/6bff32d7695b8311a856c511642c0a3836a94386))
* **hxhx:** include csharp runtime in library source sets ([e24b484](https://github.com/fullofcaffeine/hxhx/commit/e24b484418ff7d3cc4af24c1b272fc87dd66fe66))
* **hxhx:** lower csharp abstract toMap conversion ([e2c7a0b](https://github.com/fullofcaffeine/hxhx/commit/e2c7a0b6cbe2aa24948dbfff824ecf1616edb746))
* **hxhx:** lower csharp anonymous objects ([822287f](https://github.com/fullofcaffeine/hxhx/commit/822287f8d454f64db44c3e9813c6e8ac9006fcfa))
* **hxhx:** lower csharp callback bodies ([b66094d](https://github.com/fullofcaffeine/hxhx/commit/b66094d46c91c1e0ed230dbc5e7d628674957e13))
* **hxhx:** lower csharp callback switches ([4155d7d](https://github.com/fullofcaffeine/hxhx/commit/4155d7d886b15a411e6b006915ff0d3ed3b3bc0f))
* **hxhx:** lower csharp enum extract switches ([71c8f2e](https://github.com/fullofcaffeine/hxhx/commit/71c8f2edb322f62f17a1a299b1e18e2398ed335f))
* **hxhx:** lower csharp exit code parsing ([e1022ed](https://github.com/fullofcaffeine/hxhx/commit/e1022ed7a58f6adc13634df27d53e5217e7c5406))
* **hxhx:** lower csharp extern intrinsics ([f768240](https://github.com/fullofcaffeine/hxhx/commit/f768240ea67b80a4dff8190da60142940e4f1431))
* **hxhx:** lower csharp immediate lambda calls ([b4a1d0c](https://github.com/fullofcaffeine/hxhx/commit/b4a1d0c4ae3278fc5ea2676f185b1fba34e972bd))
* **hxhx:** lower csharp postfix local increments ([5b57a53](https://github.com/fullofcaffeine/hxhx/commit/5b57a535f7d2d5d075cd4fce352e05a6d3dd9f9c))
* **hxhx:** lower csharp raw intrinsics ([4d80137](https://github.com/fullofcaffeine/hxhx/commit/4d80137b4e3fbcdff5111109104a27a29b213008))
* **hxhx:** lower csharp sys exit ([e6c6add](https://github.com/fullofcaffeine/hxhx/commit/e6c6add25930d5cbde8c82265c2951a2c1bad951))
* **hxhx:** lower csharp utility callable args ([c1ec5a2](https://github.com/fullofcaffeine/hxhx/commit/c1ec5a298276274d8b7af5fc06fc75557bcaf109))
* **hxhx:** lower csharp utility switches ([5ee1ac8](https://github.com/fullofcaffeine/hxhx/commit/5ee1ac8b73e5a2c91dd9c028da361385b31904ab))
* **hxhx:** lower Lua array constructors ([8b41761](https://github.com/fullofcaffeine/hxhx/commit/8b41761a265622a7dcd8295dda4a68fe4f7e5858))
* **hxhx:** lower Lua array switch patterns ([f046ad1](https://github.com/fullofcaffeine/hxhx/commit/f046ad14f73f8efc96e073eaf20478b505263031))
* **hxhx:** lower Lua callback blocks ([625c888](https://github.com/fullofcaffeine/hxhx/commit/625c888ca8ccb0cc6859ecde2e3d666e6cd49950))
* **hxhx:** lower Lua raw try expressions ([e7613da](https://github.com/fullofcaffeine/hxhx/commit/e7613daba767079b893c49faf757c1f71842938c))
* **hxhx:** lower Lua string method calls ([53352d9](https://github.com/fullofcaffeine/hxhx/commit/53352d96bf10eea888a1eb9d5c02ad4c4ded1ddc))
* **hxhx:** lower Lua switch statements ([91ec8a0](https://github.com/fullofcaffeine/hxhx/commit/91ec8a0b73ce3a7f6499d6d90e7544174afe82cc))
* **hxhx:** map csharp runtime gate stubs ([3f23dbe](https://github.com/fullofcaffeine/hxhx/commit/3f23dbe3e7de359c02ca97fafc377ec04115d146))
* **hxhx:** map csharp system callbacks ([3013177](https://github.com/fullofcaffeine/hxhx/commit/301317706e979a73f6f42940d5eafa84e10cf2f3))
* **hxhx:** narrow csharp namespace imports ([462ee14](https://github.com/fullofcaffeine/hxhx/commit/462ee1457f7e7db647056291fc4fbde89838cc5c))
* **hxhx:** narrow csharp signal delegates ([331c83c](https://github.com/fullofcaffeine/hxhx/commit/331c83cffa9bbe5c88975ca435bc7fc81a66645f))
* **hxhx:** narrow csharp support body rendering ([847159f](https://github.com/fullofcaffeine/hxhx/commit/847159fc60b54fdc47380fc451173ca4147ad638))
* **hxhx:** narrow csharp support constructor bodies ([02f2f14](https://github.com/fullofcaffeine/hxhx/commit/02f2f149e2088ebf7d547b4e783df621e7a50180))
* **hxhx:** package csharp no-main outputs as dlls ([47fc92e](https://github.com/fullofcaffeine/hxhx/commit/47fc92ee4e5defc74fdea252f20fb56415d8013c))
* **hxhx:** package csharp source target executables ([2f96776](https://github.com/fullofcaffeine/hxhx/commit/2f96776c408e3d255b1c51c66de80b333d5eb883))
* **hxhx:** preserve csharp entry helpers ([1c92426](https://github.com/fullofcaffeine/hxhx/commit/1c92426423a06cf94c8c22a208dd8f8244ce0a24))
* **hxhx:** preserve csharp enum switch fallback ([b65ed63](https://github.com/fullofcaffeine/hxhx/commit/b65ed632bff2dd7e5caedcb79b9cd35b5aa8875b))
* **hxhx:** preserve csharp utest addcases stub ([0e10adb](https://github.com/fullofcaffeine/hxhx/commit/0e10adbc3d0f58ae3124c8269627dec7a1a60f6d))
* **hxhx:** preserve Lua embedded tracebacks ([fd238f5](https://github.com/fullofcaffeine/hxhx/commit/fd238f50f7c34cd762407a2fce8f16f9cf64e644))
* **hxhx:** preserve Lua module helper functions ([d62c818](https://github.com/fullofcaffeine/hxhx/commit/d62c818519e7eccd612a55108adc56d09426a807))
* **hxhx:** preserve Lua process exit codes ([3fdc4f7](https://github.com/fullofcaffeine/hxhx/commit/3fdc4f70b975f1fc01b60f1b25f78ae8a532f182))
* **hxhx:** provide Lua Reflect string methods ([6e2c232](https://github.com/fullofcaffeine/hxhx/commit/6e2c23249e30c32bf777b9ae802796d3348111ec))
* **hxhx:** provide Lua Sys runtime namespace ([1d5be96](https://github.com/fullofcaffeine/hxhx/commit/1d5be96744869422c02354f607b1e3a905a686a5))
* **hxhx:** qualify csharp runtime support types ([a493099](https://github.com/fullofcaffeine/hxhx/commit/a4930998f32110d33db7e25385e6563ff922bfa5))
* **hxhx:** rename csharp shadow locals ([9fcd9df](https://github.com/fullofcaffeine/hxhx/commit/9fcd9dfb4d6326ad4629b87522a9efca82e4e77a))
* **hxhx:** resolve csharp utest import scopes ([835b86b](https://github.com/fullofcaffeine/hxhx/commit/835b86ba2d6ea576d7e2b2222782f3f47456b952))
* **hxhx:** resolve root package base classes for python ([62b6cd2](https://github.com/fullofcaffeine/hxhx/commit/62b6cd2ee7e6bec38a81ced206d259aa2b15d60a))
* **hxhx:** run Lua hxml commands in Stage3 ([011d717](https://github.com/fullofcaffeine/hxhx/commit/011d717af4fea2bf8a505ae71431ebc895218d58))
* **hxhx:** sanitize csharp local declarations ([2356069](https://github.com/fullofcaffeine/hxhx/commit/23560699933fa6fe17102fd5591f1e2cf1783912))
* **hxhx:** scope csharp generated blocks ([04b4388](https://github.com/fullofcaffeine/hxhx/commit/04b438829925446f81be4f4d377a017880f4c43c))
* **hxhx:** shim csharp utility process runtime ([652e54c](https://github.com/fullofcaffeine/hxhx/commit/652e54c3dddfd1d1a24a6425a75ce90457fa1e3e))
* **hxhx:** split csharp entry wrapper from Main type ([c745570](https://github.com/fullofcaffeine/hxhx/commit/c745570ba963296159e7579fbb034b76f5693d4b))
* **hxhx:** stringify Lua string concat operands ([03922e3](https://github.com/fullofcaffeine/hxhx/commit/03922e3893e2b181c70c104be8311846e5f03416))
* **hxhx:** support focused Lua EReg regex matching ([22a1e5b](https://github.com/fullofcaffeine/hxhx/commit/22a1e5b68859b6be7e45834db4bb7bb3eae3559b))
* **hxhx:** support Lua string contains ([0d4d642](https://github.com/fullofcaffeine/hxhx/commit/0d4d64287ea13c7788461382adf6c0db71fdd93c))
* **hxhx:** support Lua string startsWith ([db471f4](https://github.com/fullofcaffeine/hxhx/commit/db471f4573172d1cb242e12b39492204f01c790d))
* **hxhx:** support Lua string substr runtime ([2843d14](https://github.com/fullofcaffeine/hxhx/commit/2843d1431a293368e58d038fbfab9aa2608bec63))
* **hxhx:** type csharp array backing access ([a8677ff](https://github.com/fullofcaffeine/hxhx/commit/a8677ffb62f4ee9d72a7e2e6e8cf6cc0a9108b6d))
* **hxhx:** type csharp function arguments as delegates ([c26844b](https://github.com/fullofcaffeine/hxhx/commit/c26844b4471ea03984497b2b0b5615275207c665))
* **hxhx:** type csharp function-return lambdas ([1ed1a24](https://github.com/fullofcaffeine/hxhx/commit/1ed1a245b542bf3454a14d83d261250674590e2e))
* **hxhx:** type csharp report factories ([ec3c91a](https://github.com/fullofcaffeine/hxhx/commit/ec3c91ab6dcf32e311473aba8f8be364ccc94019))
* **hxhx:** type csharp support fields from hints ([bd76a82](https://github.com/fullofcaffeine/hxhx/commit/bd76a8221cff994520a99b01c0ccf13e0736a9b3))
* **hxhx:** type csharp utest report support ([89696a3](https://github.com/fullofcaffeine/hxhx/commit/89696a3e0f85992377b1416dcc974e48a1027d3a))
* **hxhx:** use object equals for csharp field comparisons ([b77b8de](https://github.com/fullofcaffeine/hxhx/commit/b77b8de231a965eb697c8b139a19825945f50a12))
* **hxhx:** validate csharp assembly metadata placement ([c190728](https://github.com/fullofcaffeine/hxhx/commit/c19072863311acd8b77955486a5073e38548ff57))
* **hxhx:** validate csharp using metadata placement ([c1b9cf0](https://github.com/fullofcaffeine/hxhx/commit/c1b9cf0cd86763cdf28921d7016fc89c5b6e1f42))
* **hxhx:** wrap csharp UtilityProcess command helper ([bc88b73](https://github.com/fullofcaffeine/hxhx/commit/bc88b73d22662adcff001908e191f4e783908728))
* **hxhx:** wrap csharp UtilityProcess helper ([3f600db](https://github.com/fullofcaffeine/hxhx/commit/3f600dbb0bb4c23e0a2f8acd380f162232e3121d))
* **js:** handle missing paths in isDirectory ([af6dbe5](https://github.com/fullofcaffeine/hxhx/commit/af6dbe5200a8ea324d98ac8c2caf4951b9418be9))
* **js:** parse directives in array initializers ([ca6592e](https://github.com/fullofcaffeine/hxhx/commit/ca6592e0153c4348fe190d19bd5c04fad54549f7))
* **js:** prefer scanned static initializers ([e84b996](https://github.com/fullofcaffeine/hxhx/commit/e84b996a2d19e5ecd3f648a56237a8ee9f27e574))
* **js:** preserve throw in try catch raw lowering ([91d6f84](https://github.com/fullofcaffeine/hxhx/commit/91d6f841a155c0b896dc7e2c4d600b42e2e63135))
* **php:** dispatch super methods directly ([c5388e7](https://github.com/fullofcaffeine/hxhx/commit/c5388e750286170f324e48848e3d484e4596b02f))
* **php:** fold coalesce common-base typeString ([1513f19](https://github.com/fullofcaffeine/hxhx/commit/1513f19748b11394b74338b107ea15ab1bcfa5c4))
* **php:** fold getErrorMessage invalid-binding probes ([430688c](https://github.com/fullofcaffeine/hxhx/commit/430688cdd6a6f6dc40e16216ad5e2da3c292e577))
* **php:** fold getErrorMessage nonexhaustive probes ([16820c1](https://github.com/fullofcaffeine/hxhx/commit/16820c156857a468c40ff999e7e8fdd2a1426e19))
* **php:** fold nullable ternary helper state ([726c3ad](https://github.com/fullofcaffeine/hxhx/commit/726c3ad14bf994669d5c25083c303f94cdcbb7e8))
* **php:** iterate strings by character ([c0c472d](https://github.com/fullofcaffeine/hxhx/commit/c0c472d52826b57831479b9800a6fb75f48987a8))
* **php:** keep switch pattern locals scoped ([e8b72f8](https://github.com/fullofcaffeine/hxhx/commit/e8b72f823bc30b66af9ae1740a207abaef2de5c1))
* **php:** lower Boot class name intrinsics ([e121cf4](https://github.com/fullofcaffeine/hxhx/commit/e121cf441b37b6d18ce393ebd29fd23daf19b65b))
* **php:** lower enum ctor getName via value surface ([beebac3](https://github.com/fullofcaffeine/hxhx/commit/beebac34837d80823362397e3c9d9640e0608a62))
* **php:** lower integer switch guards ([f8b1ade](https://github.com/fullofcaffeine/hxhx/commit/f8b1ade768e0d9013a9bbdf0fa8f450e44123386))
* **php:** lower native assoc arrays ([6edc58d](https://github.com/fullofcaffeine/hxhx/commit/6edc58d390c4ad6ba293fad85f807521f5a50ca1))
* **php:** lower parsed macro switch guards ([9fd00ac](https://github.com/fullofcaffeine/hxhx/commit/9fd00ac88dfe139da38ed27e9b1833cb35485ed9))
* **php:** lower rest append prepend ([c522d20](https://github.com/fullofcaffeine/hxhx/commit/c522d20c9bb5f8fc6bccb2f4c8db2941031ebeae))
* **php:** lower rest argument arrays ([71010ea](https://github.com/fullofcaffeine/hxhx/commit/71010ea25b5b1713b776142d6b07649ebd4557f5))
* **php:** lower rest spread calls ([bc7e705](https://github.com/fullofcaffeine/hxhx/commit/bc7e705019fd2e6b834b849948059601a9dea328))
* **php:** lower rest toString ([350962f](https://github.com/fullofcaffeine/hxhx/commit/350962fb8bbda28e8e1186a7979f618b7c3dc8a7))
* **php:** lower SuperGlobal extern fields ([55495ae](https://github.com/fullofcaffeine/hxhx/commit/55495ae194ad3101436e12eec598c06148bc18a9))
* **php:** lower while return flow ([5be4d19](https://github.com/fullofcaffeine/hxhx/commit/5be4d192529b6c7cdce01e62b0793523ae5be860))
* **php:** match class-value switch cases ([61cd3f2](https://github.com/fullofcaffeine/hxhx/commit/61cd3f2fe0c290813dc2d6b397b289150e9b0d51))
* **php:** null-safe dynamic field reads ([96f89f0](https://github.com/fullofcaffeine/hxhx/commit/96f89f0420939d1e72077984cc8039340ced5ee0))
* **php:** parenthesize generated new receivers ([8e10c8d](https://github.com/fullofcaffeine/hxhx/commit/8e10c8ded90055d140f708481372178d2904ca04))
* **php:** parenthesize new receivers ([58a17d8](https://github.com/fullofcaffeine/hxhx/commit/58a17d89e7e78db8d7e0c46b2ed2d2b8a913030f))
* **php:** pass async utest argument ([2abb626](https://github.com/fullofcaffeine/hxhx/commit/2abb6264d8aeb438aea5830ef63edb9d198b3128))
* **php:** preserve abstract callable facades ([8a0ec5c](https://github.com/fullofcaffeine/hxhx/commit/8a0ec5ccb16597a6cdd67ef61cbcbf0b10988b7c))
* **php:** preserve dynamic null plus semantics ([db65fdf](https://github.com/fullofcaffeine/hxhx/commit/db65fdffb933653e010d0a3f7a1852c61d33e7db))
* **php:** preserve fake enum abstract matches ([7d5e531](https://github.com/fullofcaffeine/hxhx/commit/7d5e5314a354b3081b1f5c8721685dbef1e43311))
* **php:** preserve http callback parsing ([84dac4a](https://github.com/fullofcaffeine/hxhx/commit/84dac4a4f40e6072125ef80702240ec02f8250ec))
* **php:** preserve linear static helper bodies ([c4368f6](https://github.com/fullofcaffeine/hxhx/commit/c4368f6658cd1c09d702b6e5c6928d0340be0ae6))
* **php:** preserve macro constant payloads ([97bb802](https://github.com/fullofcaffeine/hxhx/commit/97bb802bcc306e38b099aef90429b04c842a4dcc))
* **php:** preserve method reference equality ([ab134d4](https://github.com/fullofcaffeine/hxhx/commit/ab134d4abbca194b3815ac5ab72dd4a67a7669e0))
* **php:** preserve nullable coalesce local hints ([e8fa8f3](https://github.com/fullofcaffeine/hxhx/commit/e8fa8f3735d89fa0cbbc28ffbb3e493ce163811f))
* **php:** preserve optional enum ctor args ([4be4ff7](https://github.com/fullofcaffeine/hxhx/commit/4be4ff74cb33d3eda5d6239e37cec9c3a410d306))
* **php:** preserve or-pattern captures ([8cdc51e](https://github.com/fullofcaffeine/hxhx/commit/8cdc51eb7bee5268916c07a7901d591ac21973a0))
* **php:** preserve Ref parameter mutation ([3917a3e](https://github.com/fullofcaffeine/hxhx/commit/3917a3ecd89cb48fff61f51642e1c3105716a3b2))
* **php:** provide haxe http shim ([864ca45](https://github.com/fullofcaffeine/hxhx/commit/864ca4555a235beb3aa9cf20b5ea929b55e547ae))
* **php:** recover local rest typed params ([aedbd54](https://github.com/fullofcaffeine/hxhx/commit/aedbd545422172562a4acfe3bb8cda7a5ce42e84))
* **php:** ref-capture mutating array closures ([99ef4a9](https://github.com/fullofcaffeine/hxhx/commit/99ef4a9b10c84678de0d97521d36333317589a80))
* **php:** route HashMap through map runtime ([da97574](https://github.com/fullofcaffeine/hxhx/commit/da97574b318973ff509606db2c48b0db262ffae8))
* **php:** support string method closures ([7368d9c](https://github.com/fullofcaffeine/hxhx/commit/7368d9c0aaf573d7befdc3ba3dfd1536623e5770))
* **php:** support StringTools replace extension ([4f1b4bc](https://github.com/fullofcaffeine/hxhx/commit/4f1b4bc0c13bbc746e6401df919452f0e5c3df5f))
* **php:** use strict scalar switch comparisons ([5d53efd](https://github.com/fullofcaffeine/hxhx/commit/5d53efdd072434ca81468c67acaf89ef67fdf888))
* **stage3:** rebase native top-level diagnostics ([7a919fb](https://github.com/fullofcaffeine/hxhx/commit/7a919fbd85c7d78dae4a352b38e69126161484c8))

## [0.15.20](https://github.com/fullofcaffeine/hxhx/compare/v0.15.19...v0.15.20) (2026-06-09)


### Bug Fixes

* **hxhx:** preserve semicolon after conditional #end ([22adfee](https://github.com/fullofcaffeine/hxhx/commit/22adfeeb83ffc343db0b1f490a8b91bd0b990579)), closes [#end](https://github.com/fullofcaffeine/hxhx/issues/end)

## [0.15.19](https://github.com/fullofcaffeine/hxhx/compare/v0.15.18...v0.15.19) (2026-06-09)


### Bug Fixes

* **stage0:** keep source smoke enum values typed ([d1354af](https://github.com/fullofcaffeine/hxhx/commit/d1354af16a971f444e27fff20cf034ab8435012e))

## [0.15.18](https://github.com/fullofcaffeine/hxhx/compare/v0.15.17...v0.15.18) (2026-06-09)


### Bug Fixes

* **hxhx:** preserve parser default arg string maps ([2e62fa3](https://github.com/fullofcaffeine/hxhx/commit/2e62fa3ae27e69306a2217abe92abbee7321cf81))
* **php:** add Std random runtime ([c246bbd](https://github.com/fullofcaffeine/hxhx/commit/c246bbdf0c2d06cb1145e29548cb627c103b3919))
* **php:** enforce interface casts ([e326224](https://github.com/fullofcaffeine/hxhx/commit/e326224ebbf5a642a08c476cf1b91c5e364b4900))
* **php:** fold helper nullability probes ([4ecaef4](https://github.com/fullofcaffeine/hxhx/commit/4ecaef4ce16a136ead0fe5d4c2df24190d290ba1))
* **php:** keep UInt casts numeric ([d308663](https://github.com/fullofcaffeine/hxhx/commit/d3086631727630beae5a2820f3f6e357b4e068df))
* **php:** lower array map calls ([9baf23b](https://github.com/fullofcaffeine/hxhx/commit/9baf23bed263570366ffa6315d6efe493b511dcc))
* **php:** lower map-arrow entries in typed paths ([7888dc4](https://github.com/fullofcaffeine/hxhx/commit/7888dc493eada4bc7201e1a85fc6918e8fa715d3))
* **php:** lower Syntax extern intrinsics ([7881301](https://github.com/fullofcaffeine/hxhx/commit/78813014d13c7a2ac938e2f64ad945bc17109d6b))
* **php:** normalize array dynamic casts ([405f17e](https://github.com/fullofcaffeine/hxhx/commit/405f17ec99cbb4cc219012d4d790312cbbfe048b))
* **php:** preserve explicit empty XML children ([2720e01](https://github.com/fullofcaffeine/hxhx/commit/2720e01227543a9159a658ffb3e5136818463e34))
* **php:** preserve null equality semantics ([d9dc0e1](https://github.com/fullofcaffeine/hxhx/commit/d9dc0e11ffb97003aceec56de6e03a889f24794a))
* **php:** preserve skipped optional lambda fields ([747e9c6](https://github.com/fullofcaffeine/hxhx/commit/747e9c65a90e8eb3bbb59cd8029452eb0b8b0e37))
* **php:** provide Math.random runtime shim ([8775224](https://github.com/fullofcaffeine/hxhx/commit/8775224ffbaee800eec337a4bf697941a5ddf341))
* **php:** skip nominal casts for abstracts ([cb5e512](https://github.com/fullofcaffeine/hxhx/commit/cb5e5128a363ea5cbe51cb25cdac51a580dbf554))
* **php:** skip unsafe interface name collisions ([01f8ca1](https://github.com/fullofcaffeine/hxhx/commit/01f8ca17c9ee6a5f16d288352c412b1a847b1664))

## [0.15.17](https://github.com/fullofcaffeine/hxhx/compare/v0.15.16...v0.15.17) (2026-05-11)


### Bug Fixes

* **php:** call same-class function fields ([2072f7c](https://github.com/fullofcaffeine/hxhx/commit/2072f7c2c3cd0b9ce65733a48c39109350c6d604))

## [0.15.16](https://github.com/fullofcaffeine/hxhx/compare/v0.15.15...v0.15.16) (2026-05-11)


### Bug Fixes

* **php:** preserve generic callable constructor field ([c41c9c4](https://github.com/fullofcaffeine/hxhx/commit/c41c9c4111747eb837c1a27887ada4619a5035e5))
* **php:** resolve enum constructor peer context ([244e738](https://github.com/fullofcaffeine/hxhx/commit/244e738dcf4d315849953367e4e17cae4ff29e31))
* **php:** resolve local enum constructor calls ([22dee07](https://github.com/fullofcaffeine/hxhx/commit/22dee075459429ffb73b468f6b62ae969225ab1b))
* **php:** resolve string using module aliases ([3ebe290](https://github.com/fullofcaffeine/hxhx/commit/3ebe290f2e7262ab07b866ad3dea4eef9439821c))
* **php:** support gadt enum switch lowering ([0ed6228](https://github.com/fullofcaffeine/hxhx/commit/0ed622804977072d38faf687792cc5f9bade736d))

## [0.15.15](https://github.com/fullofcaffeine/hxhx/compare/v0.15.14...v0.15.15) (2026-05-11)


### Bug Fixes

* **php:** add map comprehension helper ([19cc325](https://github.com/fullofcaffeine/hxhx/commit/19cc325cfe66de6278bdf2553d7676d10b71af10))
* **php:** dispatch abstract unary operators ([2352252](https://github.com/fullofcaffeine/hxhx/commit/235225241543f16a84dc38e00bed81463a659fd2))
* **php:** expose vector reflection toString ([367aec4](https://github.com/fullofcaffeine/hxhx/commit/367aec4b77e08e34b6d5c37d3dbcbf240a7d5375))
* **php:** fold abstract unary typeError probes ([473a6c9](https://github.com/fullofcaffeine/hxhx/commit/473a6c96dc521fb00aab260dcc4984a2fd27653a))
* **php:** snapshot abstract this in closures ([664716a](https://github.com/fullofcaffeine/hxhx/commit/664716a2e405ae50f4e34032b8a45257e5cd098d))
* **php:** support array-backed abstract push pop ([33796c3](https://github.com/fullofcaffeine/hxhx/commit/33796c32a5d4ea709038cd80238f096338b88723))
* **php:** support object array access helpers ([3f52480](https://github.com/fullofcaffeine/hxhx/commit/3f524801b8b3a31f3899850e62a2d2af48a83355))

## [0.15.14](https://github.com/fullofcaffeine/hxhx/compare/v0.15.13...v0.15.14) (2026-05-11)


### Bug Fixes

* **js:** lower optional lambda sentinel ([4e64ffb](https://github.com/fullofcaffeine/hxhx/commit/4e64ffb9dbbb6eaabe1570c76f45ba331e8bc165))
* **native-parser:** preserve typed default parameter hints ([ba5e4e5](https://github.com/fullofcaffeine/hxhx/commit/ba5e4e5cfa5331f88ac4b8c4d1487901d521feed))
* **parser:** preserve scanned default args ([f913a7c](https://github.com/fullofcaffeine/hxhx/commit/f913a7c0327e36aefe9764b652dad235308299a7))
* **parser:** preserve scanned string defaults ([46a2299](https://github.com/fullofcaffeine/hxhx/commit/46a2299a30ddda9f2ef158e3b2383bdee2f8fec1))
* **php:** add BytesInput position accessors ([f7fbc8d](https://github.com/fullofcaffeine/hxhx/commit/f7fbc8df417e71ae0560d510e8265e4dcdf5c954))
* **php:** add DateTools runtime support ([1960363](https://github.com/fullofcaffeine/hxhx/commit/196036336c67a61a06335ceb36f569e3ccc2ada3))
* **php:** add GenericStack runtime support ([91bfaa4](https://github.com/fullofcaffeine/hxhx/commit/91bfaa43470d36e3ddc79d02d33c6b21068cfc9e))
* **php:** add haxe rtti meta runtime ([b1cdc39](https://github.com/fullofcaffeine/hxhx/commit/b1cdc39685840e69207c36ee6dc8a10420a410ab))
* **php:** add Haxe serializer runtime support ([35a10f8](https://github.com/fullofcaffeine/hxhx/commit/35a10f8129b648efbc7158cec05e06f591e3fa68))
* **php:** add Int64 fromFloat support ([60288d3](https://github.com/fullofcaffeine/hxhx/commit/60288d3ff1b082c6a8b92a587e26aebb5db6034b))
* **php:** add Lambda list runtime helper ([a173d22](https://github.com/fullofcaffeine/hxhx/commit/a173d223c4b42456f316aef0c5dcf5b4a4c3a71f))
* **php:** add List runtime class checks ([f2a5fbd](https://github.com/fullofcaffeine/hxhx/commit/f2a5fbd3056dc8eaed55218056d2a5a127283c29))
* **php:** add reflect callMethod runtime ([e0b0df1](https://github.com/fullofcaffeine/hxhx/commit/e0b0df1c0f3f214c9d8d32e2c30cca2b47bb3489))
* **php:** add reflect fields runtime ([4fa5d69](https://github.com/fullofcaffeine/hxhx/commit/4fa5d6960338f8c6c4741874e9ed63494e130267))
* **php:** add simple enum helper ([93a11cc](https://github.com/fullofcaffeine/hxhx/commit/93a11cc0814dbf7da43b1213f9f95daa459a61ea))
* **php:** add Std parseFloat support ([6cf2597](https://github.com/fullofcaffeine/hxhx/commit/6cf259791eea94b85869b1839ef2a839c59bad18))
* **php:** add StringBuf runtime support ([07b5141](https://github.com/fullofcaffeine/hxhx/commit/07b514183e2c813f527607238ac0e53df92fe72c))
* **php:** add StringTools hex helper ([b7d18ab](https://github.com/fullofcaffeine/hxhx/commit/b7d18ab8d90852cd5c29dbb33dfef6096318d650))
* **php:** add Type reflection helpers ([ac0ed5a](https://github.com/fullofcaffeine/hxhx/commit/ac0ed5a3007bd6a195003ed4db85490076ba09e9))
* **php:** advance enum reflect type checks ([0d922bb](https://github.com/fullofcaffeine/hxhx/commit/0d922bb669ae3c7362c7d2e7e8e7717bdb5f3932))
* **php:** advance Gate3 Int64 and Reflect property support ([23a91df](https://github.com/fullofcaffeine/hxhx/commit/23a91dfc377115ace388bcda9a72f12d8a7a5dec))
* **php:** align numeric type checks ([21e246b](https://github.com/fullofcaffeine/hxhx/commit/21e246b29687d009a4511478747fee2d2833fcd0))
* **php:** avoid Int64 class alias collisions ([64c33e9](https://github.com/fullofcaffeine/hxhx/commit/64c33e992c6990d210ac79e45ec65025910fab55))
* **php:** bind Int64 divMod calls ([76e61a5](https://github.com/fullofcaffeine/hxhx/commit/76e61a54cd073ce46820ccb9d1d95db8decb73b4))
* **php:** bind Int64 toStr calls ([8dc2be3](https://github.com/fullofcaffeine/hxhx/commit/8dc2be36ce0a208cadd561573fa0a69df7a12ff2))
* **php:** box typed Int64 array pushes ([0877c97](https://github.com/fullofcaffeine/hxhx/commit/0877c97ef2ea147e4012eb5eb15a783186ba1455))
* **php:** call static function fields via properties ([b54d542](https://github.com/fullofcaffeine/hxhx/commit/b54d5426327ffc1f972d8c96edc0517886c0dc70))
* **php:** canonicalize runtime class checks ([4747709](https://github.com/fullofcaffeine/hxhx/commit/474770950ef7a4e66aa148501314d10ac533ef5f))
* **php:** capture scoped locals in raw try expressions ([27fb94d](https://github.com/fullofcaffeine/hxhx/commit/27fb94d69abb2b0caa5e4313037206750c893fc9))
* **php:** coerce Int64 helper arguments ([0681e72](https://github.com/fullofcaffeine/hxhx/commit/0681e72f0da76e09bd9cdf149390cfa8b051630d))
* **php:** compare class values to names ([2e12649](https://github.com/fullofcaffeine/hxhx/commit/2e126494e5f25c7c222c1be2c8828ca7ce456700))
* **php:** compare Int64 values ([863ce4c](https://github.com/fullofcaffeine/hxhx/commit/863ce4c5bf88f8e35485cb3b83a42878c31cee6b))
* **php:** compare point values to strings ([88a154d](https://github.com/fullofcaffeine/hxhx/commit/88a154dfa49883c7940a77c1d26e92d5b79a65b7))
* **php:** dispatch Int64 division ([694c244](https://github.com/fullofcaffeine/hxhx/commit/694c24449531c48dbaf03f01757a91562eaf2b4c))
* **php:** dispatch Int64 modulo ([7c04d01](https://github.com/fullofcaffeine/hxhx/commit/7c04d017d7c60d025972b0daf6b8c469c8399e81))
* **php:** emit haxe io error enum carrier ([714b337](https://github.com/fullofcaffeine/hxhx/commit/714b337b8d9e82891c68583bd5dc4d25f4125490))
* **php:** emit haxe json runtime ([f861317](https://github.com/fullofcaffeine/hxhx/commit/f86131731ff218e9ce7f5040fc89c73e7a0d2ecb))
* **php:** emit imported haxelib enum carriers ([4fdc090](https://github.com/fullofcaffeine/hxhx/commit/4fdc090fe0c03fef770f968e82cd62132049244f))
* **php:** emit rtti meta payloads ([a1a7094](https://github.com/fullofcaffeine/hxhx/commit/a1a7094deb9c31e06acfc3487456e4b64e418e6c))
* **php:** emit std enum abstract carriers ([f4cdaef](https://github.com/fullofcaffeine/hxhx/commit/f4cdaefffbdeb8ed41cb406bcaecb5914f3ee40b))
* **php:** evaluate field add-assign receivers once ([4ed673a](https://github.com/fullofcaffeine/hxhx/commit/4ed673a413dfeaa117648c930115adb375e94b0f))
* **php:** expose all enum values ([d064b9f](https://github.com/fullofcaffeine/hxhx/commit/d064b9f82b3beebddbcc3949df36c387dc5a01ed))
* **php:** expose enum constructor reflection ([4fc2a87](https://github.com/fullofcaffeine/hxhx/commit/4fc2a87b962f2581fb3e1aa2c4c9f2254eec6c51))
* **php:** expose Int64 arithmetic methods ([1d9da98](https://github.com/fullofcaffeine/hxhx/commit/1d9da989accb305e980e25e4a425dc46f8bd4c1d))
* **php:** expose Int64 divMod ([42a28d6](https://github.com/fullofcaffeine/hxhx/commit/42a28d60978520fad9b83ecf483233e6e3481648))
* **php:** expose Int64 toStr ([3965792](https://github.com/fullofcaffeine/hxhx/commit/396579249723f07c94678958f3fab1012b6feed5))
* **php:** expose value exception stack ([e55e9c1](https://github.com/fullofcaffeine/hxhx/commit/e55e9c1ee60acfe55dcd180a8466555068f5a49d))
* **php:** fold abstract overload probes ([4f084cc](https://github.com/fullofcaffeine/hxhx/commit/4f084cc188b3246e31de8b45bfa394ad330c1a58))
* **php:** fold anon type error probes ([1a6c374](https://github.com/fullofcaffeine/hxhx/commit/1a6c37410a7c89d460e01bbcba165ed5ce80129d))
* **php:** fold generic null type errors ([c152514](https://github.com/fullofcaffeine/hxhx/commit/c152514412f9b64d9817238d486ef62079c22cd3))
* **php:** fold macro rest helpers ([8f9c5e8](https://github.com/fullofcaffeine/hxhx/commit/8f9c5e8024143acc9e1fc05426935a5277cfdf5e))
* **php:** fold map literal type probes ([b2ed153](https://github.com/fullofcaffeine/hxhx/commit/b2ed153782acee8b1a9d8d13932c773ac5552f8f))
* **php:** fold optional param type probes ([e6655e1](https://github.com/fullofcaffeine/hxhx/commit/e6655e1f5e9f327ad635da3dfa14aa0097edf408))
* **php:** fold typed helper probes ([0118a10](https://github.com/fullofcaffeine/hxhx/commit/0118a10114ee08d38f0a5e192d0f9032bf5d6b63))
* **php:** guard cyclic object stringification ([ae428bb](https://github.com/fullofcaffeine/hxhx/commit/ae428bb7ca8e8656bca3d9777bef8e52f6b901b6))
* **php:** hide accessor-only fields from reflection ([bb1b36e](https://github.com/fullofcaffeine/hxhx/commit/bb1b36e4e11b9b71a34df88079714ca7573efbf1))
* **php:** honor anonymous toString fields ([8527bc6](https://github.com/fullofcaffeine/hxhx/commit/8527bc6f7c7621d980cd3ea65fc35b628b8bc444))
* **php:** implement Int64 compare ([9bb50b3](https://github.com/fullofcaffeine/hxhx/commit/9bb50b32e04a42087635c7c860167d33a340a31f))
* **php:** implement Int64 runtime basics ([e3c5005](https://github.com/fullofcaffeine/hxhx/commit/e3c50051edfa2ebf7bba555bddc05436dc85ce7f))
* **php:** implement Reflect property access ([f95ae58](https://github.com/fullofcaffeine/hxhx/commit/f95ae58580b42a1e66e47284cc4ead02d35ea238))
* **php:** implement Reflect.compareMethods ([cbe57c0](https://github.com/fullofcaffeine/hxhx/commit/cbe57c0f6c78cdf113026a39e283323b1a3c8db3))
* **php:** implement Std.parseInt ([9f330c4](https://github.com/fullofcaffeine/hxhx/commit/9f330c494ec001b1f55a0f28cbdf674fb592b44b))
* **php:** implement Type.createEmptyInstance ([5500443](https://github.com/fullofcaffeine/hxhx/commit/55004433361769cbe854d6ba8e0ebf6cc492323c))
* **php:** implement Type.createEnum ([8f8e356](https://github.com/fullofcaffeine/hxhx/commit/8f8e356a305860faf51c9567f56aab74c25f3fc7))
* **php:** implement Type.createInstance ([896e1f5](https://github.com/fullofcaffeine/hxhx/commit/896e1f535f156fae6ba06ca24b95e25a796bfdf4))
* **php:** implement Type.typeof ([4cfb8e4](https://github.com/fullofcaffeine/hxhx/commit/4cfb8e4ffe7271b7741c2e59c03bb5017bcb7df8))
* **php:** infer empty generic array specializations ([2517fc4](https://github.com/fullofcaffeine/hxhx/commit/2517fc41566bd4863e061f4a2b566d248eb81ff2))
* **php:** lower __unprotect__ helper ([c1e8c0f](https://github.com/fullofcaffeine/hxhx/commit/c1e8c0f9d5cd386eadbff8ed34874a03c67eabce))
* **php:** lower constructible generic constructors ([566cd1a](https://github.com/fullofcaffeine/hxhx/commit/566cd1a05073f89c5776381ae681de9a69db441a))
* **php:** lower function-valued property calls ([54f5fcf](https://github.com/fullofcaffeine/hxhx/commit/54f5fcf84c81313376a386064db75721ea9cdb38))
* **php:** lower imported Int64 neg ([6580e7a](https://github.com/fullofcaffeine/hxhx/commit/6580e7a5384446948313875b5e3f3fd122370bfd))
* **php:** lower Int64 bitwise not ([17635c5](https://github.com/fullofcaffeine/hxhx/commit/17635c56398de71a4b47367d84a84183a9b9780f))
* **php:** lower Int64 bitwise ops ([640087a](https://github.com/fullofcaffeine/hxhx/commit/640087a4e679d4a9f432fc9fd96307b61067d406))
* **php:** lower Int64 compat methods ([f3a00cd](https://github.com/fullofcaffeine/hxhx/commit/f3a00cd9abef2c3495882fff06038f7565195e9e))
* **php:** lower Int64 shifts ([fc56cdb](https://github.com/fullofcaffeine/hxhx/commit/fc56cdbc4235f30c0b9e4bf19c9dcb5e7afa41b4))
* **php:** lower Int64 static imports ([e08053b](https://github.com/fullofcaffeine/hxhx/commit/e08053b6af174f2d896cf6edc818b5281c199c89))
* **php:** lower Int64 subtraction ([d7a02a7](https://github.com/fullofcaffeine/hxhx/commit/d7a02a7f79f137f3d7715026a94a3ac3ae1d8ccb))
* **php:** lower nonfinite Math constants ([a88f630](https://github.com/fullofcaffeine/hxhx/commit/a88f630a7303468bd9d19f0b4c4097c69282340a))
* **php:** lower opaque raw block expressions ([7c8f596](https://github.com/fullofcaffeine/hxhx/commit/7c8f596c20ec70af5509974a1e3e67ad6322a8fa))
* **php:** lower point3 unary vector ops ([3ca753e](https://github.com/fullofcaffeine/hxhx/commit/3ca753ecabe035c16209b490da22040d610e2be1))
* **php:** lower string using extensions ([f304eb2](https://github.com/fullofcaffeine/hxhx/commit/f304eb22c73f733b268f74c5138f51d8467a7e25))
* **php:** lower type-name helper calls ([59aa5c0](https://github.com/fullofcaffeine/hxhx/commit/59aa5c0e047e20503d3aba8f4e40a335c5b24289))
* **php:** map simple enum serialization indexes ([ab8e260](https://github.com/fullofcaffeine/hxhx/commit/ab8e260cd10d9e0eb306a8da6f6935f57f725f00))
* **php:** narrow Int64 compare lowering ([0cd0b59](https://github.com/fullofcaffeine/hxhx/commit/0cd0b59993710bd045b6f07bc64e462026f2ca08))
* **php:** parse Int64 strings ([e0df760](https://github.com/fullofcaffeine/hxhx/commit/e0df7600d56fd1e2c2e6bbe7547803e5bd931e91))
* **php:** prefer builtin type values ([7748ff8](https://github.com/fullofcaffeine/hxhx/commit/7748ff8f3575e402310973d8bb5cba5c1dd6bcb4))
* **php:** prefer explicit generic static specializations ([fc892db](https://github.com/fullofcaffeine/hxhx/commit/fc892dbb468ae13c573b9fb8b79733963d254d0c))
* **php:** preserve class identity equality ([f65a46d](https://github.com/fullofcaffeine/hxhx/commit/f65a46d63acff7df5a68a86fa559a95cd67e7153))
* **php:** preserve constrained helper scanner bodies ([9fed988](https://github.com/fullofcaffeine/hxhx/commit/9fed98847bac6879cc1e24357c32e693cc36b372))
* **php:** preserve Int64 helper receiver chains ([411960e](https://github.com/fullofcaffeine/hxhx/commit/411960e036f4d7c6bd27f90cc7718494a0b6977d))
* **php:** preserve io error catch locals ([39e8c95](https://github.com/fullofcaffeine/hxhx/commit/39e8c958e52e5ee09ea5221ca70b7b6c47d56378))
* **php:** preserve null field access semantics ([c9485f8](https://github.com/fullofcaffeine/hxhx/commit/c9485f84bb1ac7130d461644c7fa9ff9f8e24f41))
* **php:** preserve optional local function args ([392b27f](https://github.com/fullofcaffeine/hxhx/commit/392b27f1893b681309171efba5653c8e608fdfb4))
* **php:** preserve real bind methods ([171bc4b](https://github.com/fullofcaffeine/hxhx/commit/171bc4bfcf1f5102601509e00269c6183b5de79d))
* **php:** preserve self return receivers ([7d76b1d](https://github.com/fullofcaffeine/hxhx/commit/7d76b1d4925b4fab700d07de5f455d8622c6a21d))
* **php:** preserve stage3 metadata payloads ([e24caf8](https://github.com/fullofcaffeine/hxhx/commit/e24caf8bc942a43aa7530dd02692784eaacf79eb))
* **php:** preserve thrown enum identity ([0910877](https://github.com/fullofcaffeine/hxhx/commit/09108775a3667b5cbfed1523e9d254c1a07f7c06))
* **php:** provide JsonParser runtime shim ([06c2374](https://github.com/fullofcaffeine/hxhx/commit/06c2374ee8fad10c70d8087119dd2b68120311ec))
* **php:** provide JsonPrinter runtime shim ([88d6230](https://github.com/fullofcaffeine/hxhx/commit/88d6230cf5fa1ca7fc365796e2472d6d6e265fbc))
* **php:** qualify imported haxe json calls ([a05f7f4](https://github.com/fullofcaffeine/hxhx/commit/a05f7f4c4e59b24d2438d48d1a7feb1670569388))
* **php:** qualify imported haxe resource calls ([7c3c0b5](https://github.com/fullofcaffeine/hxhx/commit/7c3c0b550cb67e0882018e3e5a753ed91f417a07))
* **php:** qualify imported haxe unserializer calls ([f12a3d0](https://github.com/fullofcaffeine/hxhx/commit/f12a3d0b6718108e8ca97785e94c86a4335565f1))
* **php:** qualify same-class static helper calls ([3903a31](https://github.com/fullofcaffeine/hxhx/commit/3903a313849e853c4def5757e8d07c19606fd296))
* **php:** recognize map shim runtime types ([662d598](https://github.com/fullofcaffeine/hxhx/commit/662d5983fe4573ff99e3d68dc4583ab2b16e87fb))
* **php:** reflect generic static specializations ([6682968](https://github.com/fullofcaffeine/hxhx/commit/668296896dd1dea7016a8836ca4bd1d73d8ed22e))
* **php:** reflect multi-argument generic specializations ([3315fe6](https://github.com/fullofcaffeine/hxhx/commit/3315fe67fbf52d5046e18e8a64ee8d13e7433859))
* **php:** render package class references as values ([5d980f2](https://github.com/fullofcaffeine/hxhx/commit/5d980f20316270485e7dc42261929fca50aa4f47))
* **php:** resolve unqualified enum constructor calls ([5f80453](https://github.com/fullofcaffeine/hxhx/commit/5f804533c520396b96b540229dffd9b0de29fc71))
* **php:** return iterator-compatible map keys ([7e0669d](https://github.com/fullofcaffeine/hxhx/commit/7e0669db5611277c8190cf550fdf415c8325024c))
* **php:** rewrite switch enum helper calls ([b5d1575](https://github.com/fullofcaffeine/hxhx/commit/b5d1575510480fe6ce15cb46e9c8e7f4a79174e9))
* **php:** roundtrip indexed enum serialization ([ae7de04](https://github.com/fullofcaffeine/hxhx/commit/ae7de04beef832fbd65ab657bc03cce026de40a2))
* **php:** route Int64 arithmetic ([3072a02](https://github.com/fullofcaffeine/hxhx/commit/3072a02ace5e1da7cd97b8973c88bac2c81b7759))
* **php:** route Int64 increments ([575f135](https://github.com/fullofcaffeine/hxhx/commit/575f1357f2e602829a363f09cb9b32caa0fcf427))
* **php:** route list push through runtime ([be4f52b](https://github.com/fullofcaffeine/hxhx/commit/be4f52bc01be7094d5c85ced51f9b0760ead4d5e))
* **php:** serialize List values correctly ([b2630dc](https://github.com/fullofcaffeine/hxhx/commit/b2630dcf4982b142d6571a34c030c5fc17945511))
* **php:** stringify Int64 values ([062bc73](https://github.com/fullofcaffeine/hxhx/commit/062bc73f9bf558364e55e75b2efbf222803b8fce))
* **php:** support closure bind placeholders ([f59f710](https://github.com/fullofcaffeine/hxhx/commit/f59f71078399c4a972778974a5941a69714b0a57))
* **php:** support defaulted closure args ([967268a](https://github.com/fullofcaffeine/hxhx/commit/967268ae515d353dbac72cb8d783a2656389db3c))
* **php:** tag class meta values ([ca4c23b](https://github.com/fullofcaffeine/hxhx/commit/ca4c23b9ffa190c37a0f02482417d30307af9bfc))
* **php:** tag inferred map values ([3630358](https://github.com/fullofcaffeine/hxhx/commit/3630358c79e51131b3117794186c00ddfe105642))
* **php:** tag StringMap runtime checks ([83c25fc](https://github.com/fullofcaffeine/hxhx/commit/83c25fca541a2dccc98c7731e9c7e6ab57c9bf3b))
* **php:** unwrap abstract cast constraint probes ([d85ad9d](https://github.com/fullofcaffeine/hxhx/commit/d85ad9dcba10d800178d13f16f3ce4923e4deff2))
* **php:** wire haxe Resource runtime ([8c41fad](https://github.com/fullofcaffeine/hxhx/commit/8c41fad47536a6fd5a42b1d1099b91eb6851f555))

## [0.15.13](https://github.com/fullofcaffeine/hxhx/compare/v0.15.12...v0.15.13) (2026-04-24)


### Bug Fixes

* **php:** handle optional argument defaults ([818e03b](https://github.com/fullofcaffeine/hxhx/commit/818e03bc7326ec8b0627c50d02aab022489b3d85))

## [0.15.12](https://github.com/fullofcaffeine/hxhx/compare/v0.15.11...v0.15.12) (2026-04-24)


### Bug Fixes

* **php:** add Base64 crypto shim ([7692067](https://github.com/fullofcaffeine/hxhx/commit/76920670447ace896e72f4cced3bb4b8773224d2))
* **php:** add BaseCode crypto shim ([f47f06f](https://github.com/fullofcaffeine/hxhx/commit/f47f06f2461cf024ebf1fd925515d521943c87a2))
* **php:** add Md5.make shim ([7ba067b](https://github.com/fullofcaffeine/hxhx/commit/7ba067b7fb5f6a0c9fb034596a4acc1db8f49fdd))
* **php:** add Reflect.makeVarArgs shim ([d887fe9](https://github.com/fullofcaffeine/hxhx/commit/d887fe9f50421eef9836c84a2addfccec41063f7))
* **php:** add Sha1 crypto shim ([7c4020a](https://github.com/fullofcaffeine/hxhx/commit/7c4020a74ddb1103b42c73a95bc892d5e329bcda))
* **php:** add StringTools URL helpers ([f749a28](https://github.com/fullofcaffeine/hxhx/commit/f749a28173b954f2c71191f3be72a10fee5b7fae))
* **php:** support dynamic method closures ([38d77e5](https://github.com/fullofcaffeine/hxhx/commit/38d77e5e849284c947064f1538128c396bda36e0))

## [0.15.11](https://github.com/fullofcaffeine/hxhx/compare/v0.15.10...v0.15.11) (2026-04-24)


### Bug Fixes

* **parser:** preserve static accessor bodies ([b31f355](https://github.com/fullofcaffeine/hxhx/commit/b31f355710c87afb8cbf975a2db04427cfe47e40))
* **php:** add date runtime support ([069b0d4](https://github.com/fullofcaffeine/hxhx/commit/069b0d4c7d4c07f4cdecd4b87bceef86b5900d39))
* **php:** add enum equality runtime ([8dd5105](https://github.com/fullofcaffeine/hxhx/commit/8dd51056111d2b3b552362da878f466a8a85ad38))
* **php:** add source Xml runtime seam ([1d79788](https://github.com/fullofcaffeine/hxhx/commit/1d79788d2644b23ca5fd68cec9f89bb0ff378012))
* **php:** add xml parser shim ([d620846](https://github.com/fullofcaffeine/hxhx/commit/d6208469a57b5e24757a1fe8bd75d485facb2290))
* **php:** bind instance method values ([2d95aac](https://github.com/fullofcaffeine/hxhx/commit/2d95aacec9012f60aab65ff07ef00236268a6bb1))
* **php:** bind same-instance method values ([6998154](https://github.com/fullofcaffeine/hxhx/commit/6998154e3ca1c2b84de97395310fc1b0e1d9b5ce))
* **php:** capture for-in iterables ([dbea649](https://github.com/fullofcaffeine/hxhx/commit/dbea6493b823b8b723d7d6d378b4d42ecafe0b8d))
* **php:** capture mutable closure locals ([e678247](https://github.com/fullofcaffeine/hxhx/commit/e67824797a95cc77371eb891621de2a487518b6b))
* **php:** guard xml scalar operations ([6174953](https://github.com/fullofcaffeine/hxhx/commit/617495337c1ade7ecda786f78cf1e4bebcac47bf))
* **php:** implement source-native EReg runtime ([add5676](https://github.com/fullofcaffeine/hxhx/commit/add567647de68021dfd71425cd17989d889e148b))
* **php:** lower enum constructor values ([fe73060](https://github.com/fullofcaffeine/hxhx/commit/fe73060cc2c4f295cf2aa3f4b34dbec48410d2cf))
* **php:** lower message string indexOf calls ([11125aa](https://github.com/fullofcaffeine/hxhx/commit/11125aa017c483a85319d2a2df041628a76dc3e6))
* **php:** lower split on string results ([8fe1635](https://github.com/fullofcaffeine/hxhx/commit/8fe16357b6f23cf7c9f8bfb98e9af766a9992990))
* **php:** lower string length in binary reads ([49d4ba7](https://github.com/fullofcaffeine/hxhx/commit/49d4ba7bd5c6841562cf8441272038de732c1eab))
* **php:** match xml apostrophe attribute escaping ([12291da](https://github.com/fullofcaffeine/hxhx/commit/12291da74dfbe204dcaa5a38d5c3258ad9d23e9a))
* **php:** move xml children on reparent ([ad6e47f](https://github.com/fullofcaffeine/hxhx/commit/ad6e47f342fb0fe252b4e7fb532da23b999445d2))
* **php:** preserve local closure helper names ([bd943ed](https://github.com/fullofcaffeine/hxhx/commit/bd943ed28cdc2d021ff1a16112867a8bc77937f3))
* **php:** preserve std package roots ([1c7b34e](https://github.com/fullofcaffeine/hxhx/commit/1c7b34e1f9e955acf6f7e9d0e838554070829a14))
* **php:** reject raw angles in strict xml attrs ([0a442f7](https://github.com/fullofcaffeine/hxhx/commit/0a442f7f527079fa7d41b71b4a73c568b2e7f73a))
* **php:** report xml parser node errors ([052c858](https://github.com/fullofcaffeine/hxhx/commit/052c858102dec724583f840c2701be0d620d10f2))
* **php:** resolve same-name static locals ([f4d8848](https://github.com/fullofcaffeine/hxhx/commit/f4d8848a14a6bbdd14925e574e0c315fd4f42640))
* **php:** route static property getters ([5d366f0](https://github.com/fullofcaffeine/hxhx/commit/5d366f0330f558d1c3821bad9fb3b9a5dfa661ea))
* **php:** support callable bind lowering ([eae1f40](https://github.com/fullofcaffeine/hxhx/commit/eae1f40f6dbede603f13656621e626d9459cb671))

## [0.15.10](https://github.com/fullofcaffeine/hxhx/compare/v0.15.9...v0.15.10) (2026-04-23)


### Bug Fixes

* **php:** lower locals capture loops natively ([58a891d](https://github.com/fullofcaffeine/hxhx/commit/58a891d703ea1beb3953d6fa1b91dbb57e5829f8))

## [0.15.9](https://github.com/fullofcaffeine/hxhx/compare/v0.15.8...v0.15.9) (2026-04-23)


### Bug Fixes

* **php:** add bytes io runtime ([24c5a91](https://github.com/fullofcaffeine/hxhx/commit/24c5a912ae414a3c31200f1f9db2e66fdbc8256b))

## [0.15.8](https://github.com/fullofcaffeine/hxhx/compare/v0.15.7...v0.15.8) (2026-04-23)


### Bug Fixes

* **php:** fold helper macros and std exceptions ([8164025](https://github.com/fullofcaffeine/hxhx/commit/8164025f4d762e80bf73bdfeb3b8d6cb08634cf4))
* **php:** lower expression throws and argument exceptions ([5a3e68c](https://github.com/fullofcaffeine/hxhx/commit/5a3e68c74746745f3949c47635574729fa0937d5))
* **php:** support std downcast catches ([0083cc2](https://github.com/fullofcaffeine/hxhx/commit/0083cc2be32ea02769940c7d50ad14a677a4a391))

## [0.15.7](https://github.com/fullofcaffeine/hxhx/compare/v0.15.6...v0.15.7) (2026-04-23)


### Bug Fixes

* **php:** add minimal call stack runtime ([2539019](https://github.com/fullofcaffeine/hxhx/commit/2539019a253af57a033e5d418d730b753a300256))
* **php:** route instance calls and array push ([3893983](https://github.com/fullofcaffeine/hxhx/commit/38939831004dc646ba39f8d5310f4484b5d31560))

## [0.15.6](https://github.com/fullofcaffeine/hxhx/compare/v0.15.5...v0.15.6) (2026-04-23)


### Bug Fixes

* **php:** match abstract and enum catches ([63c8f99](https://github.com/fullofcaffeine/hxhx/commit/63c8f9933feed444b6b16e3a29b9a9a81dd74c01))

## [0.15.5](https://github.com/fullofcaffeine/hxhx/compare/v0.15.4...v0.15.5) (2026-04-23)


### Bug Fixes

* **php:** preserve thrown catch payloads ([61f5d53](https://github.com/fullofcaffeine/hxhx/commit/61f5d53e1d0bbf54cbcac709444ecd2f5e250a8e))

## [0.15.4](https://github.com/fullofcaffeine/hxhx/compare/v0.15.3...v0.15.4) (2026-04-22)


### Bug Fixes

* **php:** preserve numeric suffix semantics ([11a93a2](https://github.com/fullofcaffeine/hxhx/commit/11a93a2f7298f4ba790de2800b20034fc071dc81))

## [0.15.3](https://github.com/fullofcaffeine/hxhx/compare/v0.15.2...v0.15.3) (2026-04-22)


### Bug Fixes

* **source:** lower switch break callbacks structurally ([1841e0f](https://github.com/fullofcaffeine/hxhx/commit/1841e0f54f93f0de89f98b86bcb9eb78ec118ce2))

## [0.15.2](https://github.com/fullofcaffeine/hxhx/compare/v0.15.1...v0.15.2) (2026-04-22)


### Bug Fixes

* **lua:** preserve inline conditional suffixes ([308690b](https://github.com/fullofcaffeine/hxhx/commit/308690b1daf325633a098c3c1f6b321ced494ed8))

## [0.15.1](https://github.com/fullofcaffeine/hxhx/compare/v0.15.0...v0.15.1) (2026-04-22)


### Bug Fixes

* **cs:** allow no-package native externs ([b384da6](https://github.com/fullofcaffeine/hxhx/commit/b384da66fb3249a3b0b9a381c6016f05b0ca9108))
* **java:** pass strict sys target gate ([2c1f95a](https://github.com/fullofcaffeine/hxhx/commit/2c1f95aebec2f85b9547adadbeae600d0adafef0))
* **java:** run UtilityProcess sys helper ([c4d3f2d](https://github.com/fullofcaffeine/hxhx/commit/c4d3f2d485038c65fec458f2a5d6f4cca5f7eae2))
* **stage3:** report dynamic emit exceptions ([0cc8524](https://github.com/fullofcaffeine/hxhx/commit/0cc85246427801ae5b4ec8340b140660956b6f3d))

# [0.15.0](https://github.com/fullofcaffeine/hxhx/compare/v0.14.0...v0.15.0) (2026-04-03)


### Bug Fixes

* harden stage0-policy runtime path and version guard ([41f90fa](https://github.com/fullofcaffeine/hxhx/commit/41f90faf83f99b26eb4b36de8023d7d33614a254))
* **js-native:** lower block-bodied function literals ([4d7cc33](https://github.com/fullofcaffeine/hxhx/commit/4d7cc33bebfc2ede00eac14e118cde41fcd3c3a9))
* **js-native:** stabilize switch case storage and allow Bytes ctor ([a870d8c](https://github.com/fullofcaffeine/hxhx/commit/a870d8ce6dfde500d4001be06842ef48fa90578e))
* **js-native:** unblock provider promotion lane ([e2f08db](https://github.com/fullofcaffeine/hxhx/commit/e2f08dbe20313f7476d81bba97498ba801ca482e))
* **ocaml:** bridge dispatch wrapper types for balanced tree ([d7609e4](https://github.com/fullofcaffeine/hxhx/commit/d7609e4a359f884a23505cade6470fb8b4932969))
* **ocaml:** enable runtime haxe.rtti portable fixture ([d6343a9](https://github.com/fullofcaffeine/hxhx/commit/d6343a95d9b83157589e2e85ca4e78fe82afb056))
* **ocaml:** handle Bytes encoding in HttpBase lowering ([3e10d8f](https://github.com/fullofcaffeine/hxhx/commit/3e10d8fb3cc74b0b48d34b2ca91016e92f26df39))
* **ocaml:** handle stdlib super method dispatch for PosException ([097da3e](https://github.com/fullofcaffeine/hxhx/commit/097da3e914ea4796388a2d5c53b811a583c6ccdb))
* **ocaml:** normalize class record labels and close haxe.crypto Hmac ([3a97d8c](https://github.com/fullofcaffeine/hxhx/commit/3a97d8c2c3df339ee3a60407175521a01b03bcc0))
* **ocaml:** normalize value identifiers for crypto parity ([27e1cef](https://github.com/fullofcaffeine/hxhx/commit/27e1cef0bd6d0e961488543ce432cabd3f4429cb))
* **ocaml:** restore haxe.Template.execute portable parity ([f053b49](https://github.com/fullofcaffeine/hxhx/commit/f053b49859042aa8b7b75fbafe6e457a9612628d))
* **portable:** restore sys.net runtime fixture coverage ([5cb4ec4](https://github.com/fullofcaffeine/hxhx/commit/5cb4ec4e3021c3d9b4789882660194652ddafcc2))
* **stage0:** auto-retry when build --connect handoff stalls ([3c36a96](https://github.com/fullofcaffeine/hxhx/commit/3c36a9603c44617c65cfb1b837c19a111b408b72))
* **stage3:** harden StringTools shim and warning-20 macro shims ([e8d0783](https://github.com/fullofcaffeine/hxhx/commit/e8d07833cc6773ebf2f3545c9b1165f2fbc2d23c))
* **stage3:** infer std root and harden mixed HxArray push ([1fba5f5](https://github.com/fullofcaffeine/hxhx/commit/1fba5f54ebe883b8c8f5ccdaf5a3a0177377c5fa))
* **stage3:** infer std root from .haxerc and harden source lane ([80e275c](https://github.com/fullofcaffeine/hxhx/commit/80e275c1035f2dfe71f56dfa09395179bed92b07))
* **stdlib:** add Xml override and portable fixture ([7e4e91c](https://github.com/fullofcaffeine/hxhx/commit/7e4e91cb737f78d81832a27a0d923678847ff910))
* **test-portable:** avoid nounset empty-array expansion ([6a963b8](https://github.com/fullofcaffeine/hxhx/commit/6a963b8225bd9e7cad4d698091f506489d1d9db7))
* unblock stage0 source-lane build typing seams ([a59a4ab](https://github.com/fullofcaffeine/hxhx/commit/a59a4abd40ad1e0794eabd047447d7cc06d8c688))


### Features

* add ocaml profile/runtime plan reports ([9327798](https://github.com/fullofcaffeine/hxhx/commit/93277983175ddb2fc1f4a1c8baed50d62f821e50))
* add stage0 haxe selection policy for bootstrap regen ([dcf9406](https://github.com/fullofcaffeine/hxhx/commit/dcf94063b6d39a0a96172c8e8a3b23b32ede3e1a))
* **bench:** add portable/metal M14 lanes and microbench workloads ([8738a53](https://github.com/fullofcaffeine/hxhx/commit/8738a5357ef682a1bb12e44f3ee97403df2b4aff))
* harden stage0 bootstrap regen observability ([1f49aad](https://github.com/fullofcaffeine/hxhx/commit/1f49aad649f900f740692f1948baafb1feb4faf1))
* **ocaml:** add portable auto-metalization planner report ([0f49949](https://github.com/fullofcaffeine/hxhx/commit/0f4994911f541b0b9d7d5fa1d64bd1b15f8a1ed6))
* **ocaml:** enable runtime-backed sys.thread portable lane ([bfef0ee](https://github.com/fullofcaffeine/hxhx/commit/bfef0ee81516d1cea07e720f3f485b557ee1e2a0))
* **ocaml:** harden stage0 profile contract and stdlib parity gates ([6ba908d](https://github.com/fullofcaffeine/hxhx/commit/6ba908dbe32fbd0fcf336dccd0c89deda0ac6bde))
* **plugin:** hard-cutover manifest kind to ocaml-dynlink ([a6eba86](https://github.com/fullofcaffeine/hxhx/commit/a6eba86bc34abe745def3abf715c215c39f1bc3c))
* **promotion:** add backend promotion smoke workflow ([99f0226](https://github.com/fullofcaffeine/hxhx/commit/99f0226c36f63756fd09df8d10551e5af041e9cf))
* **promotion:** add eval adapter generation lane ([6b8408a](https://github.com/fullofcaffeine/hxhx/commit/6b8408afd713ae85ec8f698f6560be5a76836e26))
* **stage3:** add native plugin host ABI and dynlink loader seam ([f6fb0e9](https://github.com/fullofcaffeine/hxhx/commit/f6fb0e948582cab4043c648d50ef593693c979c3))
* **stage4:** add native macro-module dynlink ABI and smoke lane ([033b008](https://github.com/fullofcaffeine/hxhx/commit/033b00853a667cb8b2c74ce356faa81f6448135d))
* **stdlib:** add haxe.atomic portable overrides ([4ba85c0](https://github.com/fullofcaffeine/hxhx/commit/4ba85c06710be539649ee561f6d3e3889b55b956))
* **stdlib:** close haxe.core-02 portable bucket ([7724f84](https://github.com/fullofcaffeine/hxhx/commit/7724f84a0ab9e998cebe4868246bc76f9c0e8116))
* **stdlib:** close haxe.display-01 portable bucket ([ad9c2a6](https://github.com/fullofcaffeine/hxhx/commit/ad9c2a6b750a050d339bf95af4510f7b06295ebd))
* **stdlib:** close haxe.ds portable closure bucket ([8b2151e](https://github.com/fullofcaffeine/hxhx/commit/8b2151efe6722215135974c80c18926df80fd080))
* **stdlib:** close haxe.format bucket with Json parser/printer coverage ([3550b5e](https://github.com/fullofcaffeine/hxhx/commit/3550b5e4e3cc3924c21c0b5d4a3814f226b07f7a))
* **stdlib:** close haxe.http portable bucket ([ad77715](https://github.com/fullofcaffeine/hxhx/commit/ad77715acb43be038d857dd9dc8fb64633d4f1a9))
* **stdlib:** implement Xml.parse in OCaml override ([d7b54ad](https://github.com/fullofcaffeine/hxhx/commit/d7b54ad77f5a56f04c903c54f47d4b57a7d34b5f))
* switch metal runtime planning to compiler-tracked usage ([59a2588](https://github.com/fullofcaffeine/hxhx/commit/59a2588332922f89d1115c59944c038343cba893))


### Performance Improvements

* **ocaml:** reduce portable boundary boxing for Array.join ([99e72dc](https://github.com/fullofcaffeine/hxhx/commit/99e72dc03fe36eab53093dcddaca0e5344109ca4))
* **runtime:** add adaptive HxArray typed stores with deopt ([65ff852](https://github.com/fullofcaffeine/hxhx/commit/65ff852e5ee4bb131b95d97637857c7c87738f3d))
* **runtime:** switch HxAnon to shape+slot layout ([3e76084](https://github.com/fullofcaffeine/hxhx/commit/3e76084eed476989a0186ddc7b64364d48085b6a))
* **tooling:** add HXHX_DUNE_JOBS controls for hxhx builds ([45be243](https://github.com/fullofcaffeine/hxhx/commit/45be2430d46d21c2ce11f1361cc5bd97c717ed3b))

# [0.14.0](https://github.com/fullofcaffeine/hxhx/compare/v0.13.0...v0.14.0) (2026-02-24)


### Features

* **plugin:** add reflaxe target adapter conventions ([b964eb0](https://github.com/fullofcaffeine/hxhx/commit/b964eb0b4ffb602676da36e15c66e5371f80c560))

# [0.13.0](https://github.com/fullofcaffeine/hxhx/compare/v0.12.0...v0.13.0) (2026-02-24)


### Features

* **metal:** specialize array and string lowering ([63b1f77](https://github.com/fullofcaffeine/hxhx/commit/63b1f77a9280b1da33531da8e293ead9b2f64c10))

# [0.12.0](https://github.com/fullofcaffeine/hxhx/compare/v0.11.0...v0.12.0) (2026-02-24)


### Features

* **plugin:** add source-tiered loader precedence for Stage3 ([25a8141](https://github.com/fullofcaffeine/hxhx/commit/25a814188fb3fbaa7d15010b15e03629f45b2e08))

# [0.11.0](https://github.com/fullofcaffeine/hxhx/compare/v0.10.0...v0.11.0) (2026-02-24)


### Features

* **plugin:** add backend plugin manifest schema and validation ([38c3ddc](https://github.com/fullofcaffeine/hxhx/commit/38c3ddc18fa513190f0d857c5782412fe485a117))
* **plugin:** add native .cmxs build workflow and smoke ([8c2a694](https://github.com/fullofcaffeine/hxhx/commit/8c2a694039e6d256376e32a4ebff81dbbc1810af))

# [0.10.0](https://github.com/fullofcaffeine/hxhx/compare/v0.9.8...v0.10.0) (2026-02-24)


### Features

* **hxhx:** add helper-managed stage0 connect reuse for build-hxhx ([a3844c2](https://github.com/fullofcaffeine/hxhx/commit/a3844c24054c6ba749af700c2b62dc45d011f5ee))
* **hxhx:** define ocaml_profile portable|metal contract ([855b5bb](https://github.com/fullofcaffeine/hxhx/commit/855b5bb4b3224005ced02e98cb651875b815cfb3))
* **hxhx:** speed up bootstrap regen harness and add bench tooling ([d7089e1](https://github.com/fullofcaffeine/hxhx/commit/d7089e1c772b9be8ef93bb71f524528fd06baff1))

## [0.9.8](https://github.com/fullofcaffeine/hxhx/compare/v0.9.7...v0.9.8) (2026-02-20)


### Bug Fixes

* **gate2:** default Darwin resolution skip to fail-fast ([70f7891](https://github.com/fullofcaffeine/hxhx/commit/70f7891d27161606f071a4f541c8d4e22df60b7a))

## [0.9.7](https://github.com/fullofcaffeine/hxhx/compare/v0.9.6...v0.9.7) (2026-02-20)


### Bug Fixes

* **gate2:** eliminate stage3 .hxml Darwin segfault ([917b7e1](https://github.com/fullofcaffeine/hxhx/commit/917b7e1a1f6306fc6b964a82049bcec23a3b6506))

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
