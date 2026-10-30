# [0.37.0](https://github.com/fullofcaffeine/hxhx/compare/v0.36.1...v0.37.0) (2026-10-30)


### Bug Fixes

* **ocaml:** keep selected instance calls out of callback mapping ([0fda23e](https://github.com/fullofcaffeine/hxhx/commit/0fda23e5697273f8f61bcaf2e82845a8eac9dc1e))


### Features

* **hxhx:** convert macro arguments and results to haxe.macro.Expr ([4ce993b](https://github.com/fullofcaffeine/hxhx/commit/4ce993baaf304b1f367c2a661f6b15b195a93a69))

## [0.36.1](https://github.com/fullofcaffeine/hxhx/compare/v0.36.0...v0.36.1) (2026-10-30)


### Bug Fixes

* **stage3:** compile sort comparators that use Reflect.compare ([66eb404](https://github.com/fullofcaffeine/hxhx/commit/66eb404337220dc89f526fe59c9517ce1b831961))
* **stage3:** route bodiless Array methods through the runtime ([328cb83](https://github.com/fullofcaffeine/hxhx/commit/328cb83e795689111322447dc22c0225bb1b7e17))

# [0.36.0](https://github.com/fullofcaffeine/hxhx/compare/v0.35.0...v0.36.0) (2026-10-30)


### Bug Fixes

* **ci:** own current weekly evidence failures ([30c5543](https://github.com/fullofcaffeine/hxhx/commit/30c5543c9a8a5c150db31b5e2512fbe616d75e41))
* **ci:** rebalance compiler-focused-1 shard ([c341b09](https://github.com/fullofcaffeine/hxhx/commit/c341b09928a3fe8274367e87826dc54a297da52f))
* **ci:** tighten failure-signature matching after review ([4f1cd2e](https://github.com/fullofcaffeine/hxhx/commit/4f1cd2ede6dc493d9d78ce29e3d64fa7aae9de72))
* **ocaml:** produce values for local compound assignments ([c6fb69a](https://github.com/fullofcaffeine/hxhx/commit/c6fb69a3d5d95d9fc78191427f20a09344476e9b))
* **ocaml:** type compound values for operators and order statement updates ([d7b63a6](https://github.com/fullofcaffeine/hxhx/commit/d7b63a631010db4b1b4c794a05b1d6908685f13c))


### Features

* **ci:** let a matching failure signature own a red required check ([c84ac57](https://github.com/fullofcaffeine/hxhx/commit/c84ac577c232442ce32e6bacaf1c8ef0a010cac4))

# [0.35.0](https://github.com/fullofcaffeine/hxhx/compare/v0.34.0...v0.35.0) (2026-10-29)


### Bug Fixes

* **backends:** preserve guarded control and native array behavior ([18a2520](https://github.com/fullofcaffeine/hxhx/commit/18a2520a30703b108440bea40c807c519a198aab))
* **backends:** preserve saved output functions and Python local identities ([7e0d67c](https://github.com/fullofcaffeine/hxhx/commit/7e0d67c21f2e3a96a4aed6950c50d99e59b8105a))
* **bootstrap:** stop replacing authored Eof constructors ([700b1ff](https://github.com/fullofcaffeine/hxhx/commit/700b1ff999a34ee7e13dc6b5eb9f08b32c808c99))
* **build:** normalize macro-host output overrides ([691db29](https://github.com/fullofcaffeine/hxhx/commit/691db29b8c8d1c1f2b6f44dd55a977dcbf1e02ce))
* **build:** stop bootstrap monitor process trees ([bb64742](https://github.com/fullofcaffeine/hxhx/commit/bb647425a7ad46e246a63f4f7bd1d03de2bfdc64))
* **build:** stop compiler children before releasing a failed build ([e954e50](https://github.com/fullofcaffeine/hxhx/commit/e954e5068a125ca4c6909b3c08f35a4dd6c1b556))
* **build:** write captured progress through inherited stderr ([6e924a5](https://github.com/fullofcaffeine/hxhx/commit/6e924a5d4d3efcbbb0eb7448b93fdba434e06ef9))
* **ci:** classify the abstract meta type constant ([d980531](https://github.com/fullofcaffeine/hxhx/commit/d9805310b5449958cab2b1e162ea0f2e6c3f0d0c))
* **ci:** classify the constructor test observer ([a20e5cb](https://github.com/fullofcaffeine/hxhx/commit/a20e5cb8915f6077e821993e6d17f8dfa9b11228))
* **ci:** expose the downloaded Neko compiler ([abb1f18](https://github.com/fullofcaffeine/hxhx/commit/abb1f1899c62bffd8b24b781982524f131ae66ad))
* **ci:** follow the core guard group in example coverage checks ([a4fd549](https://github.com/fullofcaffeine/hxhx/commit/a4fd5499c34340e86a710e91cfe412e11278ba74))
* **ci:** inventory immutable alias and class type labels ([873c49a](https://github.com/fullofcaffeine/hxhx/commit/873c49a9814b6ca4cc68b2ff935b56d1981f0096))
* **ci:** inventory the native target revision check ([b93979c](https://github.com/fullofcaffeine/hxhx/commit/b93979c26fce3f2d19c98d857c7e3246e7ff9d71))
* **ci:** inventory the native target revision check ([#48](https://github.com/fullofcaffeine/hxhx/issues/48)) ([6217af3](https://github.com/fullofcaffeine/hxhx/commit/6217af3f2eeb011a2136e2bfba8af5c34f7e9efe))
* **ci:** inventory the open method parameter type label ([54e30e7](https://github.com/fullofcaffeine/hxhx/commit/54e30e705306dec6bf67b14ed7554a65efdd7ad9))
* **ci:** inventory the shared OCaml input check ([dd3b444](https://github.com/fullofcaffeine/hxhx/commit/dd3b4445200b102c451b9a5055773fcd4c2d429f))
* **ci:** keep the target reuse contract working on bash 3.2 ([0fbb919](https://github.com/fullofcaffeine/hxhx/commit/0fbb9195cb614f62e11a541029abc7996eb58d79))
* **ci:** provide focused runtime test dependencies ([d55f819](https://github.com/fullofcaffeine/hxhx/commit/d55f81924fc9dbe6bc970bb3a50ef6edf669a871))
* **ci:** recognize the Lua extern binding plan ([8b6da6b](https://github.com/fullofcaffeine/hxhx/commit/8b6da6b4daf0987624aa950ba9d3be493d022297))
* **ci:** record the Boolean array runtime reference ([b38277b](https://github.com/fullofcaffeine/hxhx/commit/b38277bdd711894041b18d847e2a4645ac330fea))
* **ci:** report independent shard failures together ([a3905f1](https://github.com/fullofcaffeine/hxhx/commit/a3905f1bb58f4b688b3668b67c59dd474694e67b))
* **ci:** scan executable Haxe for forbidden dynamic types ([f3f0ca6](https://github.com/fullofcaffeine/hxhx/commit/f3f0ca6b9550ce76b7515a14291bb7be659367a2))
* **ci:** scope OCaml installation to Ubuntu sources ([852b902](https://github.com/fullofcaffeine/hxhx/commit/852b90205ddb435be72a868ae14932c3f508641c))
* **ci:** split costly standalone guard checks across runners ([a2cea9f](https://github.com/fullofcaffeine/hxhx/commit/a2cea9f2a113ec4047b3baa2b79bae067aef0642))
* **ci:** split nested compiler regression chains ([b39dab4](https://github.com/fullofcaffeine/hxhx/commit/b39dab4858590ed8ed0883a3bb98b73a00de8c8f))
* **cli:** retain discovered SDK across cwd changes ([c5a75a5](https://github.com/fullofcaffeine/hxhx/commit/c5a75a5c09a623b52067a7ea37e35aa778db89e0))
* **compiler:** expand authored extern inline bodies with exact types ([f980de2](https://github.com/fullofcaffeine/hxhx/commit/f980de2336183a73b3785815630457a700b69e72))
* **compiler:** infer omitted inputs from constructor calls ([051ca43](https://github.com/fullofcaffeine/hxhx/commit/051ca4367c9cedcaa6854bc15605e6ca790156f2))
* **compiler:** isolate call argument projection dependencies ([10396c9](https://github.com/fullofcaffeine/hxhx/commit/10396c983a8fa12574fcc3123880d4cbafdf29f2))
* **compiler:** preserve assignment rules in inline storage ([0b75532](https://github.com/fullofcaffeine/hxhx/commit/0b755324a499acaba7f8046015c7f61ade77be5b))
* **compiler:** preserve callable constraints through publication ([547a7e8](https://github.com/fullofcaffeine/hxhx/commit/547a7e8d2e4c42640a187d16cfb1b16c8ff2ccb1))
* **compiler:** preserve callback facts through target emission ([38b99b4](https://github.com/fullofcaffeine/hxhx/commit/38b99b4b4782de7bfd285e9ccef6403d9e4d9913))
* **compiler:** preserve callbacks in required inline bodies ([d8a4df8](https://github.com/fullofcaffeine/hxhx/commit/d8a4df8a9b09daf6cc73b435c822d6d3dc818d50))
* **compiler:** preserve compound updates across control expressions ([a96443a](https://github.com/fullofcaffeine/hxhx/commit/a96443a7a66286d88af8fa501bdc2e3548c75e65))
* **compiler:** preserve expression metadata through typed lowering ([a18c0a1](https://github.com/fullofcaffeine/hxhx/commit/a18c0a171ae7d733b68ce3ee4c0c32bedf46303f))
* **compiler:** preserve null enum constants through native matching ([4a21dad](https://github.com/fullofcaffeine/hxhx/commit/4a21dad19cd13165d7ea79a2419befa388bcee9b))
* **compiler:** preserve selected static calls across backends ([742743e](https://github.com/fullofcaffeine/hxhx/commit/742743eae0c1b78add7d4f972adccaad61979eb0))
* **compiler:** preserve typed key-value iteration and captures ([59a7a22](https://github.com/fullofcaffeine/hxhx/commit/59a7a225d9357fcb1f2356e8cffbca4f7141797e))
* **compiler:** preserve unchanged feature selection identity ([e42a49c](https://github.com/fullofcaffeine/hxhx/commit/e42a49cfd7516d51d32f6d097dfb1b17a71a1886))
* **compiler:** retain children with inherited constructors ([1c2176e](https://github.com/fullofcaffeine/hxhx/commit/1c2176e1aacfae257c210bd0e8893f55511f536c))
* **compiler:** retain class methods exposed by record types ([1f9797e](https://github.com/fullofcaffeine/hxhx/commit/1f9797e3c9df9e2f4a9c9dcfe4cca53a53452d13))
* **compiler:** retain inferred untyped callable constraints ([f63785a](https://github.com/fullofcaffeine/hxhx/commit/f63785afb59b0a3e48d2e4d3b87fa58cd4d6624e))
* **compiler:** retain logging operands through control lowering ([9a72d59](https://github.com/fullofcaffeine/hxhx/commit/9a72d595e045fb760836c3a276b1fb6913f245b3))
* **compiler:** retain prepared function control regions ([0c2b5b1](https://github.com/fullofcaffeine/hxhx/commit/0c2b5b1086ec4d2e35aad1d424b67f596dbed630))
* **compiler:** retain structurally typed record callbacks ([e71fafe](https://github.com/fullofcaffeine/hxhx/commit/e71fafee076c1f8d23eb2b7554d9a12939d74870))
* **compiler:** retain typed storage for unchecked indices ([bc72db1](https://github.com/fullofcaffeine/hxhx/commit/bc72db13eac28e70431e83feee17c56299973e6c))
* **compiler:** select declared multi-type construction providers ([7b31df8](https://github.com/fullofcaffeine/hxhx/commit/7b31df887f28e556bbced75e2f9a1ae05bac4442))
* **control:** preserve declared block result types ([e54da2a](https://github.com/fullofcaffeine/hxhx/commit/e54da2a77af1f20d57b145f65a86172e245a2a4f))
* **control:** preserve discarded source block effects ([641e263](https://github.com/fullofcaffeine/hxhx/commit/641e26397884bd5698a09b01efd0f67b3e60d244))
* **core:** preserve abstract property access and setter writeback ([02107d7](https://github.com/fullofcaffeine/hxhx/commit/02107d713f6b7902da057f77a1887e0db00afae3))
* **core:** preserve checked constructor and inline call facts ([28b4a80](https://github.com/fullofcaffeine/hxhx/commit/28b4a80974deb522c953f15a19df63ba7c1894c7))
* **core:** preserve integer abstract text conversions ([1807e9d](https://github.com/fullofcaffeine/hxhx/commit/1807e9da1c61272f87fc5a70c364a47f12c208f5))
* **core:** preserve recursive types and declared enum values ([b0720c7](https://github.com/fullofcaffeine/hxhx/commit/b0720c73ab5ffb3b560f41445393f91273783a30))
* **core:** retain diagnostic results through typed replay ([db79ad3](https://github.com/fullofcaffeine/hxhx/commit/db79ad309c8559be129a4810eb5e95ff0832f743))
* **cpp:** allow writes to native primitive parameters ([827ae8d](https://github.com/fullofcaffeine/hxhx/commit/827ae8d2c92de527fb4db36c6c20db51a913552b))
* **cpp:** bind standard integer recovery for numeric values ([f3ff70f](https://github.com/fullofcaffeine/hxhx/commit/f3ff70f600205c884def993a3bde52a6378dd3c1))
* **cpp:** bind standard Math constants without static storage ([1bdaa8b](https://github.com/fullofcaffeine/hxhx/commit/1bdaa8b82f3ee784a9a470b88ee1329f146f3613))
* **cpp:** compare managed enum payloads safely ([4621c0d](https://github.com/fullofcaffeine/hxhx/commit/4621c0d68fb7880de529785c6a58e688ed03960b))
* **cpp:** concatenate primitive values stored as Dynamic ([70ace7a](https://github.com/fullofcaffeine/hxhx/commit/70ace7adc635863fe14631c2e366e3069ab9c820))
* **cpp:** construct typed enum payloads with rooted arguments ([03f3d99](https://github.com/fullofcaffeine/hxhx/commit/03f3d99868fb7064086eb906bcae5e827baae57a))
* **cpp:** distinguish generic receiver applications ([66196be](https://github.com/fullofcaffeine/hxhx/commit/66196be7e3787677f02eed4dc865185fc8eeda81))
* **cpp:** evaluate unused values after inlining ([a4e3e83](https://github.com/fullofcaffeine/hxhx/commit/a4e3e831437b940f4dd8b395f7e88cea8eb024c9))
* **cpp:** execute substring calls through Unicode source ([ba06391](https://github.com/fullofcaffeine/hxhx/commit/ba063916bfc712a5ada18228b99536af078f5272))
* **cpp:** implement exact integer bitwise operations ([9429c9b](https://github.com/fullofcaffeine/hxhx/commit/9429c9b3ee8f1415ec964ffa7ed7c1b9af43f135))
* **cpp:** lower bitwise compound assignments ([cb7da97](https://github.com/fullofcaffeine/hxhx/commit/cb7da978dd021c4cbcd86aef865f78b0de6d3188))
* **cpp:** match scalar abstracts using proven backing storage ([ed0c20f](https://github.com/fullofcaffeine/hxhx/commit/ed0c20f4f4098461b442584922f91ff89efb2d96))
* **cpp:** preserve aggregate string conversion effects ([ecb8f74](https://github.com/fullofcaffeine/hxhx/commit/ecb8f74e65c3132b5bfc784a2ef5d9c2320ffdf9))
* **cpp:** preserve anonymous record assignment behavior ([9507bd0](https://github.com/fullofcaffeine/hxhx/commit/9507bd0d8e46543a5814cc903fca9d0d258faf8b))
* **cpp:** preserve declared native unary operations ([c99aedf](https://github.com/fullofcaffeine/hxhx/commit/c99aedf6593dc3ce6a4e36d9344515e5e2c95a65))
* **cpp:** preserve Float literal bits and native defaults ([8d7fa36](https://github.com/fullofcaffeine/hxhx/commit/8d7fa367a2cae872d6b4c5f8529db45d01bfe0a5))
* **cpp:** preserve inferred and discarded class values ([b18b376](https://github.com/fullofcaffeine/hxhx/commit/b18b376de1b460d5b343a5e929a714a1e4e93762))
* **cpp:** preserve Int64 values across Dynamic storage ([292c0d4](https://github.com/fullofcaffeine/hxhx/commit/292c0d4eb5ccf5351f22bbf1673bba2a765fe40a))
* **cpp:** preserve numeric values through managed Map writes ([e1d0496](https://github.com/fullofcaffeine/hxhx/commit/e1d04969a30c35cfc9a0516a2cebc7b19a81d74d))
* **cpp:** preserve stored static function values ([8e2c5fe](https://github.com/fullofcaffeine/hxhx/commit/8e2c5fe6f65f7f9c17b31bdb717a697b7bebaaad))
* **cpp:** preserve typed integer remainder behavior ([1ead173](https://github.com/fullofcaffeine/hxhx/commit/1ead1739cc50055863b6eaa10b7a5cf057b37347))
* **cpp:** preserve typed string search and equality regressions ([0bc2c9c](https://github.com/fullofcaffeine/hxhx/commit/0bc2c9c468919de4006edc4812e6bf0b5bca3cee))
* **cpp:** preserve values through structural record recovery ([6cb2b27](https://github.com/fullofcaffeine/hxhx/commit/6cb2b277f9a2ed7a8c8ecd8cab4033a594ccd078))
* **cpp:** preserve values when string copying fails ([58b0a7d](https://github.com/fullofcaffeine/hxhx/commit/58b0a7d242d62d202f5755d5a74ceea5660e9758))
* **cpp:** read native String lengths through typed fields ([127645a](https://github.com/fullofcaffeine/hxhx/commit/127645aacc1ca094635d97ebecd7d426120a4463))
* **cpp:** recover callable arrays from Dynamic storage ([d390d67](https://github.com/fullofcaffeine/hxhx/commit/d390d6730a115ecd9e53492654d1d4257235377f))
* **cpp:** retain native Map calls during shared preparation ([3ebbb02](https://github.com/fullofcaffeine/hxhx/commit/3ebbb02b5eab65bf23636f8f57cd022f39d2623a))
* **cpp:** retain receivers for stored instance methods ([4c03faf](https://github.com/fullofcaffeine/hxhx/commit/4c03faf14aa6164d4b401fc34e27adbe9bd42441))
* **cpp:** retain selected static methods through grouping ([2c407eb](https://github.com/fullofcaffeine/hxhx/commit/2c407eb6bc721bcac5b9619575e5b2c6d6e25d67))
* **cpp:** skip erased equality discovery for primitive operands ([c31e56f](https://github.com/fullofcaffeine/hxhx/commit/c31e56f8587c898ed51685b4c28fcbf90c6e6524))
* **cs:** emit typed callback control and range loops ([1d6bb99](https://github.com/fullofcaffeine/hxhx/commit/1d6bb994c6c744b86772c180556bb30c6874dcc6))
* **cs:** preserve exhaustive enum switch result assignment ([ac3494e](https://github.com/fullofcaffeine/hxhx/commit/ac3494ea200ca25a181f81263bc25cdfcc61b566))
* **cs:** preserve imported source class owners ([1d5d055](https://github.com/fullofcaffeine/hxhx/commit/1d5d05591c33d3648ee2c66ff764d732d057ef6c))
* **cs:** preserve unsafe statement scopes ([7308c3d](https://github.com/fullofcaffeine/hxhx/commit/7308c3dd04a9b0d950812e3308ffa7a2d6b4f9c0))
* **dev:** keep Beads imports out of checkout hooks ([8efb213](https://github.com/fullofcaffeine/hxhx/commit/8efb2138056d6ac790d39406d8d6bbc7a540b003))
* **dev:** keep Beads imports out of checkout hooks ([#50](https://github.com/fullofcaffeine/hxhx/issues/50)) ([7cfd95d](https://github.com/fullofcaffeine/hxhx/commit/7cfd95d1f47eeb596bd53c1067f85465673225f8))
* **hxhx:** bind native methods before argument effects ([7997d4a](https://github.com/fullofcaffeine/hxhx/commit/7997d4a04a59b017c07842776b9b83de461a7f84))
* **hxhx:** complete source visitors for guarded switches ([7a38978](https://github.com/fullofcaffeine/hxhx/commit/7a38978d16a64b9b51ad65b475a93fccabb0c913))
* **hxhx:** do not resolve value receiver chains as types in macro selection ([de8171c](https://github.com/fullofcaffeine/hxhx/commit/de8171ce0789f0598c6019d0a042db7ce62c25da))
* **hxhx:** give native Int64 values mutable shared words ([3d64c51](https://github.com/fullofcaffeine/hxhx/commit/3d64c516c13ea42540a923abafc3b08c2b0c61ec))
* **hxhx:** keep macro traversal before declaration typing ([291cffd](https://github.com/fullofcaffeine/hxhx/commit/291cffd7b7c63c131b9277aba1ab26dc3513179c))
* **hxhx:** keep ordinary compiles and registered macros working with declaration selection ([e49744e](https://github.com/fullofcaffeine/hxhx/commit/e49744e26a8abcc04f5a1a884fd52b350ecd695e))
* **hxhx:** preserve Boolean string conditions ([0439456](https://github.com/fullofcaffeine/hxhx/commit/0439456466aaf42bbe050adbb1bc9d481edf9423))
* **hxhx:** preserve extern overloads and native host bindings ([8a7a72f](https://github.com/fullofcaffeine/hxhx/commit/8a7a72fcef4634709f06ff0a75aaf0ecc18373e3))
* **hxhx:** preserve full bodies under standard-library paths ([1294839](https://github.com/fullofcaffeine/hxhx/commit/1294839c81d8c8e5751594f7507af815c47dd67d))
* **hxhx:** print the macro scope-gap count only when tracing ([c8b714d](https://github.com/fullofcaffeine/hxhx/commit/c8b714d7d784fe7d1f0136b3a82e0f6ba6096622))
* **hxhx:** read emission maps through typed APIs ([5d9b233](https://github.com/fullofcaffeine/hxhx/commit/5d9b233419b6c04e19d6fa2df041f6b1c520cd94))
* **hxhx:** reject method capture on a null receiver ([d0e2eaf](https://github.com/fullofcaffeine/hxhx/commit/d0e2eafa47e9d9b131816f8388e40a9ad32d93bd))
* **hxhx:** reset the runtime module set between compiler requests ([0a52914](https://github.com/fullofcaffeine/hxhx/commit/0a52914e3bc8f1be4c83a39b8effd3266d1c904c))
* **hxhx:** resolve generic alias declaration providers ([353c559](https://github.com/fullofcaffeine/hxhx/commit/353c5595b8d00e3919eec62fbb93e580615fe918))
* **hxhx:** retain exact external instance-call owners ([c4782b5](https://github.com/fullofcaffeine/hxhx/commit/c4782b5a77ea195fa20454de0bfa90360ca98ccd))
* **hxhx:** retain named rest overload selections ([76ccede](https://github.com/fullofcaffeine/hxhx/commit/76ccedeffb945e42341772eec81a31eb6500b6b1))
* **hxhx:** retain overload implementation ownership ([e092b95](https://github.com/fullofcaffeine/hxhx/commit/e092b95d81142806443f71b82be5db246633c956))
* **hxhx:** retain untyped host call operands ([078389d](https://github.com/fullofcaffeine/hxhx/commit/078389d39ba821dcbf88ce3b26aefab9781a18dd))
* **hxhx:** retire obsolete bootstrap parser repairs ([faf55ae](https://github.com/fullofcaffeine/hxhx/commit/faf55aeb6fec627b0ad1c2c006217c6a82142b58))
* **hxhx:** select the Stage3 root module by its requested path ([9504217](https://github.com/fullofcaffeine/hxhx/commit/95042172003f026c7b92ad942bbfc64c7102f0fd))
* **hxhx:** type modules the macro pass loads in no-output compiles ([3b485a7](https://github.com/fullofcaffeine/hxhx/commit/3b485a758ce4d732732621a57db88f45123117df))
* **js:** distinguish class markers from type names ([0412d00](https://github.com/fullofcaffeine/hxhx/commit/0412d00275a1f4d83ba31c8edda48d4ba6604b11))
* **js:** emit shared comprehension append operations ([2726b38](https://github.com/fullofcaffeine/hxhx/commit/2726b388d5f609e4815710e665e732f7ba989537))
* **js:** emit the selected property deletion operator ([37693f1](https://github.com/fullofcaffeine/hxhx/commit/37693f1db548dcb0c96313121d64478b04717e63))
* **js:** execute field initializer control with owned locals ([647d7a5](https://github.com/fullofcaffeine/hxhx/commit/647d7a55678e80850cb09cf6c2ce5dc64523f1f4))
* **js:** isolate guarded switch attempt bindings ([63be90a](https://github.com/fullofcaffeine/hxhx/commit/63be90a2a1869978078e4f043c9a0440f3ee9dbe))
* **js:** lower exact enum constructor values ([e01fb06](https://github.com/fullofcaffeine/hxhx/commit/e01fb06ae9bab57a1a5e52e5c9df71d2e4cbc068))
* **js:** lower syntax calls through their selected API owner ([e193bed](https://github.com/fullofcaffeine/hxhx/commit/e193bed3b39fdacf09a3802a09101b78038c7eb3))
* **js:** prepare feature selection before backend emission ([cf1412c](https://github.com/fullofcaffeine/hxhx/commit/cf1412c3fdbe49f1f06ffbd041fd17ec43fd28d7))
* **js:** preserve abstract backing values and conditional conversions ([d4b435c](https://github.com/fullofcaffeine/hxhx/commit/d4b435c80ae7fd348054ac7f019facef5a9534e9))
* **js:** preserve array pair iteration semantics ([7bce997](https://github.com/fullofcaffeine/hxhx/commit/7bce9970fbb26abdf26f82cdd04a84b15dac40bd))
* **js:** preserve authored providers and startup bindings ([125006b](https://github.com/fullofcaffeine/hxhx/commit/125006b29607a6399c4c77352f5774e0fabedf7a))
* **js:** preserve core Array runtime type operands ([d1cc374](https://github.com/fullofcaffeine/hxhx/commit/d1cc3740c9f847fc18ad573f1b73f517c4cf7428))
* **js:** preserve core String runtime type operands ([f8f9d94](https://github.com/fullofcaffeine/hxhx/commit/f8f9d9443cd48bb19776b0a67232a1cb9ab78704))
* **js:** preserve generic superclass initialization ([7450ab7](https://github.com/fullofcaffeine/hxhx/commit/7450ab73221b96fdce08b6b27efaac6af92824b4))
* **js:** preserve host ownership of plain extern classes ([e59da5a](https://github.com/fullofcaffeine/hxhx/commit/e59da5aad12fc44420dc67fa1cd1fcd39e9c4bda))
* **js:** preserve indexed compound assignment destinations ([3cfef5e](https://github.com/fullofcaffeine/hxhx/commit/3cfef5e8cc18ea1c406f3cdf8802986ec8660b3c))
* **js:** preserve nullable integer parsing through switch extraction ([bbda5d6](https://github.com/fullofcaffeine/hxhx/commit/bbda5d6b2352bdb4afcfdd853c5148fdaf63917a))
* **js:** preserve ordinary startup capture bindings ([9c383b0](https://github.com/fullofcaffeine/hxhx/commit/9c383b0f2b8c463af68e15fc7185f8765df0a29a))
* **js:** preserve resolved catch types and class ancestry ([3c4f558](https://github.com/fullofcaffeine/hxhx/commit/3c4f558f7287d505a53180e300958fe83cae53cc))
* **js:** resolve native externs when their values are used ([aee246e](https://github.com/fullofcaffeine/hxhx/commit/aee246e5f9556464039bfc5e313cef7ec9ff929a))
* **js:** retain selected enum pattern declarations ([2fc9a09](https://github.com/fullofcaffeine/hxhx/commit/2fc9a09e42d90577069bf56d807189f7f73f4c12))
* **js:** retain syntax calls across statement arguments ([bf20d89](https://github.com/fullofcaffeine/hxhx/commit/bf20d89266cfa8f8d09e49838e53b10e2bde4b32))
* **js:** separate unary operators from signed operands ([c895e09](https://github.com/fullofcaffeine/hxhx/commit/c895e097c64a32161f9b9c3118c8de4315dbc6a4))
* **js:** use typed Map providers for collection syntax ([1eb01ff](https://github.com/fullofcaffeine/hxhx/commit/1eb01ff9000e4687abb239d5d76f8923da7078ee))
* **lexer:** decode and validate string escapes consistently ([f5d3a65](https://github.com/fullofcaffeine/hxhx/commit/f5d3a6535208708df22ad9d853c3d8e54d1a69c9))
* **loader:** index secondary fallback sources once ([64e128c](https://github.com/fullofcaffeine/hxhx/commit/64e128c7dbac32a43f93ff0f07a5e14ca9fb4b6a))
* **loader:** preserve source identity across path spellings ([f5788e6](https://github.com/fullofcaffeine/hxhx/commit/f5788e63d254543c823636dd3b996dc9c2574761))
* **lua:** emit typed classes and preserve protected control flow ([d156640](https://github.com/fullofcaffeine/hxhx/commit/d156640a4f5cd6c3df8972d23bf1f769aecd01cc))
* **lua:** resolve explicitly named extern values ([b289232](https://github.com/fullofcaffeine/hxhx/commit/b289232874cab808f4798fd1d5d5aa82763d3ba1))
* **lua:** select target standard-library providers ([f07aa63](https://github.com/fullofcaffeine/hxhx/commit/f07aa639186843102e9a3aa0be7c907e07a68ded))
* **macro-host:** keep metadata parsing in the expression module ([98859a6](https://github.com/fullofcaffeine/hxhx/commit/98859a6d929dd5373761a090a3e2dc2a70cc380d))
* **macro-host:** use compiler type-parameter substitution ([27c65e9](https://github.com/fullofcaffeine/hxhx/commit/27c65e908aa666ab30c951ab3fb3069c39acd0cd))
* **macros:** preserve source groups in target quotations ([176a448](https://github.com/fullofcaffeine/hxhx/commit/176a448200a2133f4efbf2a9271027b0620c3b1f))
* **macros:** reject target scopes in source processing ([a0fe452](https://github.com/fullofcaffeine/hxhx/commit/a0fe452bbdb08179843833e72805de1f91e4a539))
* **native:** retain exact Java and C# constructor owners ([bc9ad96](https://github.com/fullofcaffeine/hxhx/commit/bc9ad962db0f4413e933894f217150691ef42070))
* **neko:** align native String constructor reachability ([d85303d](https://github.com/fullofcaffeine/hxhx/commit/d85303dc4258c1f2f6d7e60c32b24141bcef1441))
* **neko:** bind forward calls and lower stack primitives ([03b530f](https://github.com/fullofcaffeine/hxhx/commit/03b530fca9c7ddcdecef09475b9d3bc2b88d0297))
* **neko:** complete optional local call arguments ([f59e0b9](https://github.com/fullofcaffeine/hxhx/commit/f59e0b90f034ebf629dd1d2ac5810c6abb542348))
* **neko:** count enum payloads by their storage type ([6f735b9](https://github.com/fullofcaffeine/hxhx/commit/6f735b9f6989b02a44c319cbd8f4aedd0d9770c1))
* **neko:** execute native string slices and inline calls ([064fa92](https://github.com/fullofcaffeine/hxhx/commit/064fa9270b0aabf8d2e4983f1f0622f4a84ba24a))
* **neko:** join arrays through the native runtime ([638647e](https://github.com/fullofcaffeine/hxhx/commit/638647e72d09392c0d6134257e13ced3bc143bf6))
* **neko:** lower native array allocation and copies ([6d5a734](https://github.com/fullofcaffeine/hxhx/commit/6d5a734df27793d861cc2de8e0f13ff8fbb52fc4))
* **neko:** lower native string byte reads ([85f9654](https://github.com/fullofcaffeine/hxhx/commit/85f965487ecdd15a4adcf20842d3bdc12186b52a))
* **neko:** preserve declared static function values ([4504b5c](https://github.com/fullofcaffeine/hxhx/commit/4504b5c87fb799aed9af76584dadb58a6160bb51))
* **neko:** preserve inherited construction on one receiver ([87c1e51](https://github.com/fullofcaffeine/hxhx/commit/87c1e5125399d357cd3d9792be08adcaf5b7345d))
* **neko:** preserve optional arguments in both layouts ([841cc0a](https://github.com/fullofcaffeine/hxhx/commit/841cc0a8352a30d769d07c4fa2ed8a73d1f06ace))
* **neko:** preserve recursive abstract helper calls ([dd71344](https://github.com/fullofcaffeine/hxhx/commit/dd71344d27376f52495cf9470a530d793cb9a897))
* **neko:** read enum payloads through the Array provider ([39b8690](https://github.com/fullofcaffeine/hxhx/commit/39b86907701aeb4bad64654213d18524bf4d1c9e))
* **neko:** retain typed enum-abstract helpers and values ([ffdf0b7](https://github.com/fullofcaffeine/hxhx/commit/ffdf0b7109be3c6f9623e814930d1b3dbc4e54d5))
* **neko:** route exact standard type checks to shared predicate ([1e1cc64](https://github.com/fullofcaffeine/hxhx/commit/1e1cc648fd4c103dbe0cf823e07866cfa73db609))
* **neko:** select target standard-library sources before typing ([7dd0ce3](https://github.com/fullofcaffeine/hxhx/commit/7dd0ce3b2d37e0c652e3a5f6f85954763210925d))
* **neko:** separate parenthesized expression statements ([ca6fdf9](https://github.com/fullofcaffeine/hxhx/commit/ca6fdf9d0c08acdbb66500d8d028bfb3d38cc20b))
* **neko:** throw on ordinary field reads from null ([635f43c](https://github.com/fullofcaffeine/hxhx/commit/635f43c78142d63688182f9ef3ae9d0e64bc599b))
* **ocaml:** accept exact qualified standard Map identities ([f7b6c58](https://github.com/fullofcaffeine/hxhx/commit/f7b6c588713507a3759881ff01072ece1733e794))
* **ocaml:** adapt class casts to structural object fields ([4759de3](https://github.com/fullofcaffeine/hxhx/commit/4759de3338aa8b6c8b8f87919ef1c7fa734001ab))
* **ocaml:** adapt enum callbacks on generic class calls ([db7e27a](https://github.com/fullofcaffeine/hxhx/commit/db7e27ad80506555c660e1873089766657284ad6))
* **ocaml:** adapt generic arrays at runtime call boundaries ([2b4d8cd](https://github.com/fullofcaffeine/hxhx/commit/2b4d8cd2825facbf0d4c94307ae562c8f1d70de2))
* **ocaml:** admit checked Float extern signatures ([15cdec6](https://github.com/fullofcaffeine/hxhx/commit/15cdec65f598e110caccc6dbce58facf22786b55))
* **ocaml:** admit checked null caches in recursive modules ([7137c18](https://github.com/fullofcaffeine/hxhx/commit/7137c18e8adb7b5a4030680dcc57ba1124da4505))
* **ocaml:** admit nullable strings at the exception boundary ([9760dfe](https://github.com/fullofcaffeine/hxhx/commit/9760dfe480bdc8177c643dff6ba2b7e47b7ad0c2))
* **ocaml:** admit safe recursive modules with literals ([63fb7c3](https://github.com/fullofcaffeine/hxhx/commit/63fb7c3f29e688e7db7b3ed20e311f7ffd2dd6db))
* **ocaml:** align inspection and fixtures with initializer call plans ([4edd352](https://github.com/fullofcaffeine/hxhx/commit/4edd3526b44fecf752afd973548ac7b49897deb7))
* **ocaml:** align typed character codes with EOF detection ([746048d](https://github.com/fullofcaffeine/hxhx/commit/746048d1d418cea4ec9ead4d737f9caf5ee3ffac))
* **ocaml:** authorize dynamic bool literal boxing ([6d4a9ce](https://github.com/fullofcaffeine/hxhx/commit/6d4a9cefd9ca88b89443db270837a5ef095d6b54))
* **ocaml:** authorize null throw runtime use ([a2b7fc3](https://github.com/fullofcaffeine/hxhx/commit/a2b7fc3dab3e1fa242fb14a79dd7c62bb1d93afe))
* **ocaml:** authorize nullable string conversions ([c1c18da](https://github.com/fullofcaffeine/hxhx/commit/c1c18da897e2fd655802d554c49cfeddaf315ad5))
* **ocaml:** authorize Type.typeof runtime uses ([9696b3a](https://github.com/fullofcaffeine/hxhx/commit/9696b3ae507a166f690c3f283387d3adbd26e4e5))
* **ocaml:** bind enum result evidence to exact producers ([d7063bf](https://github.com/fullofcaffeine/hxhx/commit/d7063bf9cd7af8dfcd6c6703c973aad686d06132)), closes [#92](https://github.com/fullofcaffeine/hxhx/issues/92)
* **ocaml:** bind extern calls to checked native exports ([732fee1](https://github.com/fullofcaffeine/hxhx/commit/732fee13fd2478027b2f0184275c48fb41814c8e))
* **ocaml:** bind saved output functions to the native runtime ([1a0e3e4](https://github.com/fullofcaffeine/hxhx/commit/1a0e3e4b896c438910cb905dc7f73448b0b93b22))
* **ocaml:** box exact enum producers in nullable method results ([50ffc5b](https://github.com/fullofcaffeine/hxhx/commit/50ffc5b4f32e2952b720c9bbf09c1140df8e6bb4))
* **ocaml:** box nullable strings at Dynamic boundaries ([62bbf73](https://github.com/fullofcaffeine/hxhx/commit/62bbf73b174508ba123373c935cbe269d95e9153))
* **ocaml:** build only emitted switch defaults ([fc5e6f0](https://github.com/fullofcaffeine/hxhx/commit/fc5e6f099d8676b206d6ce00441ef694d074596b))
* **ocaml:** check native interface method dispatch ([d31a47f](https://github.com/fullofcaffeine/hxhx/commit/d31a47fa2c39b65089d4d7553fedd15052f1ec66))
* **ocaml:** clear predicate plans during request cleanup ([31772ad](https://github.com/fullofcaffeine/hxhx/commit/31772ad170dd64facdf19a3bc561408f9c03716d))
* **ocaml:** close nullable carrier gaps found in review ([6e815a1](https://github.com/fullofcaffeine/hxhx/commit/6e815a1d94ce7ac79a6d2a5bf4b75f472dacab97))
* **ocaml:** compare enums and preserve call operand order ([ba72d2d](https://github.com/fullofcaffeine/hxhx/commit/ba72d2d6c9f305810d352f0af583d500d255a679))
* **ocaml:** compare generic values with Haxe runtime equality ([35f2159](https://github.com/fullofcaffeine/hxhx/commit/35f2159d9db51b61996ac304a55293f013739202))
* **ocaml:** convert concrete values in Dynamic casts ([b712518](https://github.com/fullofcaffeine/hxhx/commit/b7125181792ea6afb8b175e2d9d4dfb60257c22d))
* **ocaml:** convert exact callback return values ([48f0880](https://github.com/fullofcaffeine/hxhx/commit/48f0880517f8b7c14337eacbb88f87c9b34a0257))
* **ocaml:** convert nullable enum results from module functions ([ca17699](https://github.com/fullofcaffeine/hxhx/commit/ca176992113d6da7b1cf00275ac7170efcc5b3b7))
* **ocaml:** convert nullable enums at direct method returns ([46b5cc7](https://github.com/fullofcaffeine/hxhx/commit/46b5cc732fdd49c1bcca26393f8905a99cbf6d3d))
* **ocaml:** convert typed Array element arguments ([140d335](https://github.com/fullofcaffeine/hxhx/commit/140d335945be74371aeaaeec45014367601190f9))
* **ocaml:** count validated Void returns in report coverage ([678dc89](https://github.com/fullofcaffeine/hxhx/commit/678dc8903144916365dd459a54cf3c46bb281f1b))
* **ocaml:** distinguish repeated lambda view evaluations ([1108fe4](https://github.com/fullofcaffeine/hxhx/commit/1108fe4eafce00ed4e0318889e089710b7dcaefc))
* **ocaml:** emit checked integer bitwise expressions ([72ddca4](https://github.com/fullofcaffeine/hxhx/commit/72ddca44a3a4168d2153088055d395bc9cc9c8f0))
* **ocaml:** emit the exact module class inventory ([d188b44](https://github.com/fullofcaffeine/hxhx/commit/d188b440184869f42c4508bfc36511f797129e50))
* **ocaml:** escape effect without identifier collisions ([60c5e3e](https://github.com/fullofcaffeine/hxhx/commit/60c5e3e579263b75f3b5c30b66fe5aa05c7e8fde))
* **ocaml:** escape effect without identifier collisions ([093ce6d](https://github.com/fullofcaffeine/hxhx/commit/093ce6dcae7bcd1153c6bb9416caf1c9b3ae5c6e))
* **ocaml:** execute authored instance field initializers ([56f2f3c](https://github.com/fullofcaffeine/hxhx/commit/56f2f3cb84a082d5f940f55d064889cb0bd5a840))
* **ocaml:** execute authored StringTools fields and code calls ([49b7f8a](https://github.com/fullofcaffeine/hxhx/commit/49b7f8a8b10a627a13303ab0d159434ad2de50a4))
* **ocaml:** execute lowered array comprehensions ([5967588](https://github.com/fullofcaffeine/hxhx/commit/5967588a67713fc7b1f769360650d41266c92f88))
* **ocaml:** execute selected constructors and parameter defaults ([527abbe](https://github.com/fullofcaffeine/hxhx/commit/527abbe002ff94db784daa037661cd862cbaa8d9))
* **ocaml:** export generic array helpers from recursive modules ([b4998a6](https://github.com/fullofcaffeine/hxhx/commit/b4998a6e15b985e210ab3f1fd8c10357cf45e907))
* **ocaml:** export nullable record and float declarations ([0fc53b1](https://github.com/fullofcaffeine/hxhx/commit/0fc53b1503f2b49365e3b42d29a7a76985ee1088))
* **ocaml:** export selected Int64 word getters ([455e1f4](https://github.com/fullofcaffeine/hxhx/commit/455e1f47933429acf67f5db7b24ebc87a4a401bc))
* **ocaml:** expose enum-value reflection ([0a2de2d](https://github.com/fullofcaffeine/hxhx/commit/0a2de2d77fd43d32db11991a7ca113779eb73f9c))
* **ocaml:** group record field initializer expressions ([03e9c93](https://github.com/fullofcaffeine/hxhx/commit/03e9c937ff1008399d09aa086d53bc03946729d3))
* **ocaml:** group recursive enum and class types ([fa79bbc](https://github.com/fullofcaffeine/hxhx/commit/fa79bbc62768893f9c5e497a3eda709fb62bbde9))
* **ocaml:** hard-cut unplanned throw syntax ([58fa932](https://github.com/fullofcaffeine/hxhx/commit/58fa932fd9f615e96bdef9115a8cc1e90cdce555))
* **ocaml:** ignore local reads after a direct return ([59833af](https://github.com/fullofcaffeine/hxhx/commit/59833af7665fe2586d6cc8c867987b10c666d573))
* **ocaml:** infer captured callback runtime representations ([e9364f6](https://github.com/fullofcaffeine/hxhx/commit/e9364f62006d23f77d13d2dfc3ac8b898feb7d8e))
* **ocaml:** initialize constructor fields once ([33bc040](https://github.com/fullofcaffeine/hxhx/commit/33bc0408725f7ada5fd2de68de2dad7acfe23540))
* **ocaml:** invoke the explicitly selected main module ([3602224](https://github.com/fullofcaffeine/hxhx/commit/3602224cb3d1c99c519947e76c60aa463aa48ce3))
* **ocaml:** isolate callback origin data from compiler host ([8f8a488](https://github.com/fullofcaffeine/hxhx/commit/8f8a488a1ced3d6754822ff9e5f6fe74587e1325))
* **ocaml:** keep callback adapter parameters distinct ([2ca6f28](https://github.com/fullofcaffeine/hxhx/commit/2ca6f28f14d1af4c33061ee0ec53e8d478361329))
* **ocaml:** keep live type inspection in compiler macros ([0b32b53](https://github.com/fullofcaffeine/hxhx/commit/0b32b53a9b008e9b26a7fcf6f02165a2008ce46a))
* **ocaml:** keep macro APIs out of the report CLI ([9ec2460](https://github.com/fullofcaffeine/hxhx/commit/9ec246005dbe7c7cda8f3e62b91fe1a97cd1048b))
* **ocaml:** keep nullable local updates in the native carrier ([0976250](https://github.com/fullofcaffeine/hxhx/commit/0976250c25370840d398c0567c8c74967928afff))
* **ocaml:** keep object map keys stable after mutation ([ed68ada](https://github.com/fullofcaffeine/hxhx/commit/ed68ada412356f3ccc301b3c91ae31662c598051)), closes [#92](https://github.com/fullofcaffeine/hxhx/issues/92)
* **ocaml:** keep one native carrier for nullable Int and Float locals ([9d14a01](https://github.com/fullofcaffeine/hxhx/commit/9d14a01b60cc9647ce6f6873e2f1e0e40280b57b))
* **ocaml:** keep the Stage3 Xml shim family out of emitted std bodies ([2c58a0f](https://github.com/fullofcaffeine/hxhx/commit/2c58a0fb321d1e5c42eb1497c4faadaf7b4eae48))
* **ocaml:** limit native binding admission to extern classes ([89cfd6a](https://github.com/fullofcaffeine/hxhx/commit/89cfd6a2db753fdf1754a94bada18d7329eee811))
* **ocaml:** lower Int field compound updates and String.charAt ([a1f2419](https://github.com/fullofcaffeine/hxhx/commit/a1f24191ae9fe6a6e141c0153354e0537ac09ab8))
* **ocaml:** match qualified enum patterns by selected member ([5579a49](https://github.com/fullofcaffeine/hxhx/commit/5579a49077fbee2837615d944e2a953fc45bd7f8))
* **ocaml:** name runtime EReg.match by its runtime export ([6b386f2](https://github.com/fullofcaffeine/hxhx/commit/6b386f246c79c4055ced5dc520a8f3b17a1e84cd))
* **ocaml:** omit constructors for module field owners ([2d244da](https://github.com/fullofcaffeine/hxhx/commit/2d244da0b0ebde01352ecbb7b88a2ccac3ada5c8))
* **ocaml:** order class methods by captured method values ([2b7a8d5](https://github.com/fullofcaffeine/hxhx/commit/2b7a8d58c0f4053a9364e7251e45a665039cf878))
* **ocaml:** order local function and class dependencies ([54f1913](https://github.com/fullofcaffeine/hxhx/commit/54f191336398d73844a19a86bc423226312593fd))
* **ocaml:** pass optional primitive parameters in the nullable carrier ([e65bc56](https://github.com/fullofcaffeine/hxhx/commit/e65bc56db2797dbcce76f2be98b016700beb3469))
* **ocaml:** place module types before function chunks ([325624a](https://github.com/fullofcaffeine/hxhx/commit/325624a743a8aec92104fa55b7394fcc58717071))
* **ocaml:** plan calls in field initializers ([f2aab41](https://github.com/fullofcaffeine/hxhx/commit/f2aab41de9be4cf1d3510a8e79b4d7b93556cbb0))
* **ocaml:** preserve admitted native function bodies ([526c8ab](https://github.com/fullofcaffeine/hxhx/commit/526c8abb0361e91f38d197b3299021fb6c702407))
* **ocaml:** preserve admitted native function bodies ([#47](https://github.com/fullofcaffeine/hxhx/issues/47)) ([df96656](https://github.com/fullofcaffeine/hxhx/commit/df96656ce1333540a24a229fcb64af9b3839e8fd))
* **ocaml:** preserve authored initializer groups ([d5ec8f8](https://github.com/fullofcaffeine/hxhx/commit/d5ec8f8a508ebf6108715a920021826e50e816de))
* **ocaml:** preserve callback identity across calls and returns ([73de48a](https://github.com/fullofcaffeine/hxhx/commit/73de48ae01f7a4b679ebf982675389665d66bb68))
* **ocaml:** preserve caught enum identity across rethrows ([a89ee75](https://github.com/fullofcaffeine/hxhx/commit/a89ee75ccb8e56fa6cd33464fa13027f5bf6717b))
* **ocaml:** preserve checked Dynamic Boolean control ([7928e60](https://github.com/fullofcaffeine/hxhx/commit/7928e604f5da6d0df697f72e46fcd26d4aeb6995))
* **ocaml:** preserve class identity and declared field storage ([049a4cb](https://github.com/fullofcaffeine/hxhx/commit/049a4cbc4bb6b08722709478b917c54eb53deb77))
* **ocaml:** preserve class identity in structural method views ([b0ad456](https://github.com/fullofcaffeine/hxhx/commit/b0ad456854f8d9ffd5884d3b043ce7f824e24fc7))
* **ocaml:** preserve class kinds in shared declarations ([e0c3e77](https://github.com/fullofcaffeine/hxhx/commit/e0c3e7797dbea6c15d05dc0c21ccfdbc79f2fb86))
* **ocaml:** preserve class values through generic callbacks ([ec5c77c](https://github.com/fullofcaffeine/hxhx/commit/ec5c77cd522399ffc6d7fe14b28db238742b52f3))
* **ocaml:** preserve direct returns through wrappers ([06d7054](https://github.com/fullofcaffeine/hxhx/commit/06d7054ab9ef0d6edfa367e77a88fe75b3ce8227))
* **ocaml:** preserve Dynamic array call arguments ([1ded6db](https://github.com/fullofcaffeine/hxhx/commit/1ded6db112008d270d784db4cc3552bf004326b6))
* **ocaml:** preserve dynamic enum payload values ([54a86cb](https://github.com/fullofcaffeine/hxhx/commit/54a86cb1e9c0d282b2e5ede44e933a90526a399b))
* **ocaml:** preserve Dynamic returns from block closures ([8ec1d88](https://github.com/fullofcaffeine/hxhx/commit/8ec1d889acc6c79f17f668e59f6152aeeefd3db0))
* **ocaml:** preserve enum identity across nullable values ([bde3ac2](https://github.com/fullofcaffeine/hxhx/commit/bde3ac218e833dddcf4b75d088d4f07e4610b4f5))
* **ocaml:** preserve enum storage in nullable arguments ([243b931](https://github.com/fullofcaffeine/hxhx/commit/243b931a665cdba8e2dc16d5f0b49574b518a78e))
* **ocaml:** preserve enum values across exception handlers ([cb97b65](https://github.com/fullofcaffeine/hxhx/commit/cb97b658aacc5f1cedee2d6e93f71b90990f2a3f))
* **ocaml:** preserve Float types in mixed arithmetic ([0a3f0d2](https://github.com/fullofcaffeine/hxhx/commit/0a3f0d2809e133a867d722cacf7b7c279b9c22a8))
* **ocaml:** preserve generic callback result types ([b489337](https://github.com/fullofcaffeine/hxhx/commit/b489337e3e5231fd0f7e8b6c556051a748840af0))
* **ocaml:** preserve generic callbacks beside optional arguments ([bddbbb6](https://github.com/fullofcaffeine/hxhx/commit/bddbbb60d8a2eab29fb2ab03def6c08d55484b82))
* **ocaml:** preserve generic values and field updates ([75bba84](https://github.com/fullofcaffeine/hxhx/commit/75bba84be4a51ecfe693dc2ad6ced6560352c98f))
* **ocaml:** preserve Int instance-field updates ([04e791b](https://github.com/fullofcaffeine/hxhx/commit/04e791b713d993b927d340b64846c5f39eb4619b))
* **ocaml:** preserve Int32 arguments at integer call boundaries ([994867e](https://github.com/fullofcaffeine/hxhx/commit/994867e5e980c01363796741d687aa1239046891))
* **ocaml:** preserve Int32 string values and effects ([c4e398a](https://github.com/fullofcaffeine/hxhx/commit/c4e398a3e92736585e1c2958185076b87c061a28))
* **ocaml:** preserve integer call results and operand order ([20f14d0](https://github.com/fullofcaffeine/hxhx/commit/20f14d0a82c91fe21ba4e24bbb414740f3538ca5))
* **ocaml:** preserve map exports and omit inline cells ([3583e42](https://github.com/fullofcaffeine/hxhx/commit/3583e422eb9de49f007fadb112edf6df70b0dec5))
* **ocaml:** preserve map identity across nullable values ([b8ef4ac](https://github.com/fullofcaffeine/hxhx/commit/b8ef4ac9d7f010dbd74ffef0ebfc9b56673a3740))
* **ocaml:** preserve nested map lookup receivers ([efebdee](https://github.com/fullofcaffeine/hxhx/commit/efebdeeb379b2b6288166d652e91c022c8311ecf))
* **ocaml:** preserve nested throws and Boolean array values ([fe0b29e](https://github.com/fullofcaffeine/hxhx/commit/fe0b29ee8f126cb0069544ca9b3228f024b153c3))
* **ocaml:** preserve nullable callback invocation ([740328e](https://github.com/fullofcaffeine/hxhx/commit/740328e09a6f75226386044da8a154fe80042266))
* **ocaml:** preserve nullable enum aliases at arguments ([42b3133](https://github.com/fullofcaffeine/hxhx/commit/42b31336f2b30003f750795a288823e08cdf5c26))
* **ocaml:** preserve nullable enum local storage ([fde62b2](https://github.com/fullofcaffeine/hxhx/commit/fde62b2415e62629a0a3c62496697f4328377087))
* **ocaml:** preserve nullable map return storage ([a15ac16](https://github.com/fullofcaffeine/hxhx/commit/a15ac16328ae22279e9afb29c9d807d737b37fb8))
* **ocaml:** preserve optional bounds on selected runtime calls ([ab13231](https://github.com/fullofcaffeine/hxhx/commit/ab1323194fdbcd5ba8dd44104b7c48f4d8912e03))
* **ocaml:** preserve optional enum payloads ([6806cd8](https://github.com/fullofcaffeine/hxhx/commit/6806cd84f604ffa75e2815f750be3744ffd6693b))
* **ocaml:** preserve proven enum result carriers ([609b3e7](https://github.com/fullofcaffeine/hxhx/commit/609b3e71b00b89265c06227ec3641d1912e1a264))
* **ocaml:** preserve records in native enum payloads ([90f61dd](https://github.com/fullofcaffeine/hxhx/commit/90f61dd827df6faf7b6e4f91e7ad4cc30283c7fa))
* **ocaml:** preserve returned calls through ordered bindings ([7563fe4](https://github.com/fullofcaffeine/hxhx/commit/7563fe485e7b8355456f58c76d46707fbb770fdf))
* **ocaml:** preserve runtime type values in enum payloads ([f784fcc](https://github.com/fullofcaffeine/hxhx/commit/f784fcc1d6a32ac5b32ff80f6312cd3b8042342d))
* **ocaml:** preserve saved Array.push receivers ([3688091](https://github.com/fullofcaffeine/hxhx/commit/3688091801856bfdabb7f1da9eac74a9b1119285))
* **ocaml:** preserve selected array call behavior ([3532325](https://github.com/fullofcaffeine/hxhx/commit/35323254c253ebbc448165f7accd076c86f0e5d0))
* **ocaml:** preserve stored callback arguments and identity ([9eed8d3](https://github.com/fullofcaffeine/hxhx/commit/9eed8d35871a01089899268d0a440cf6c65e3c5f))
* **ocaml:** preserve unchecked range value conversions ([97ccf7a](https://github.com/fullofcaffeine/hxhx/commit/97ccf7ad9ec19aa639e07b6c02538d8aee9a2e54))
* **ocaml:** preserve values across generic instance callbacks ([ff22d16](https://github.com/fullofcaffeine/hxhx/commit/ff22d167f73ddd64ea96f2ebba90aadad2d62bb1))
* **ocaml:** project parenthesized expressions into shared target facts ([810fae8](https://github.com/fullofcaffeine/hxhx/commit/810fae8ca985237f8774ed01d3fa659184df1c35))
* **ocaml:** qualify generated exception primitives ([5367152](https://github.com/fullofcaffeine/hxhx/commit/5367152417b0cc2dace29813e3268cb56188df86))
* **ocaml:** qualify typed enum reflection patterns ([8f30913](https://github.com/fullofcaffeine/hxhx/commit/8f30913fdfe64770c4cce2c5fa45bf858f2e4844))
* **ocaml:** raise Null Access for null Float updates and run operands first ([60763e7](https://github.com/fullofcaffeine/hxhx/commit/60763e722d67979e765dc5dee15282d938e1e425))
* **ocaml:** recognize arrays through typed predicates ([8576571](https://github.com/fullofcaffeine/hxhx/commit/8576571962528fcd8e5543ceff7da9a11ad88c55))
* **ocaml:** recover array storage through abstract casts ([ce6cd6f](https://github.com/fullofcaffeine/hxhx/commit/ce6cd6f12e6676c448f2e57b08f04e50b0eb09d9))
* **ocaml:** recover enums from structural field storage ([665d396](https://github.com/fullofcaffeine/hxhx/commit/665d396bf72733be1e5aea08b9b7c46e2dff1f64))
* **ocaml:** recover optional maps at required call boundaries ([3fd11cb](https://github.com/fullofcaffeine/hxhx/commit/3fd11cb96e48ee7ec96d4d39c365329ceacac92e))
* **ocaml:** reject unsupported callback layouts before selection ([fc1d410](https://github.com/fullofcaffeine/hxhx/commit/fc1d41070a6b94deeb4e1fea3917944d3bddaa41))
* **ocaml:** report independent recursive module failures ([9fa33f9](https://github.com/fullofcaffeine/hxhx/commit/9fa33f98feee61b3befbe59de0d2c0bb67ac1583))
* **ocaml:** restore native target proof checks ([f3172f6](https://github.com/fullofcaffeine/hxhx/commit/f3172f6d2d587cd9a05851408a8da8eb58faac5a))
* **ocaml:** retain array contents through Dynamic ([4f57195](https://github.com/fullofcaffeine/hxhx/commit/4f5719501b529d7ede47291dd4621e29d6b507fe))
* **ocaml:** retain captured record callback types ([5cc753e](https://github.com/fullofcaffeine/hxhx/commit/5cc753eff01d5af8f153eacce4b4099ee8af9e79))
* **ocaml:** retain direct instance method signatures ([6986e71](https://github.com/fullofcaffeine/hxhx/commit/6986e717c94af6c9b80fc241bda5ef231de14ab7))
* **ocaml:** retain Dynamic results of selected calls ([da5e369](https://github.com/fullofcaffeine/hxhx/commit/da5e3698a39c725275b060f3408b5c55c88280c2))
* **ocaml:** retain enum callback and inherited export types ([4c327f4](https://github.com/fullofcaffeine/hxhx/commit/4c327f45e4407761a1ae18d70c36a00a268d0f62))
* **ocaml:** retain implicit exception provider members ([a10daf2](https://github.com/fullofcaffeine/hxhx/commit/a10daf25e6b831cfb730ab3910705167fa07f014))
* **ocaml:** retain Int32 declaration signatures ([3f56adc](https://github.com/fullofcaffeine/hxhx/commit/3f56adc251f28f159370d81a823fe6921ae65876))
* **ocaml:** retain map pair storage through iterator temporaries ([c8c5110](https://github.com/fullofcaffeine/hxhx/commit/c8c51104892f84569dbd2bfaf8b79b4aa05179bc))
* **ocaml:** retain nullable callback declarations ([d4d54cd](https://github.com/fullofcaffeine/hxhx/commit/d4d54cd7c83b5b951f0a373428bef98268e8471d))
* **ocaml:** retain optional nested array signatures ([11bc2fe](https://github.com/fullofcaffeine/hxhx/commit/11bc2fe502b7836f53af4774371694819f70a44c))
* **ocaml:** retain provider-owned ancestor declarations ([905bc52](https://github.com/fullofcaffeine/hxhx/commit/905bc5240bed675f6e329486fb07e3ecc98d44b2))
* **ocaml:** retain recursive class and constructor signatures ([b07c91f](https://github.com/fullofcaffeine/hxhx/commit/b07c91f88e5f88ca109a41a881945c555aa4b03a))
* **ocaml:** retain reflection exclusions for selected calls ([35e532d](https://github.com/fullofcaffeine/hxhx/commit/35e532d9785f6a0e1d705618320095b47ef9d92c))
* **ocaml:** retain runtime class identity through typed catches ([99796e4](https://github.com/fullofcaffeine/hxhx/commit/99796e4d9ebdd18319e78de20fbbe125eac12363))
* **ocaml:** retain selected static call owners ([51a44ad](https://github.com/fullofcaffeine/hxhx/commit/51a44adb699807cffe6f980aa7e30e947160b1fd))
* **ocaml:** retain shared function signatures ([8c55d78](https://github.com/fullofcaffeine/hxhx/commit/8c55d78b93ea3cc107463399f9c3443dda95e73b))
* **ocaml:** retain signatures for extended key-value records ([1f95244](https://github.com/fullofcaffeine/hxhx/commit/1f9524485a41f66b00799f8621f7ed8b2f83f09c))
* **ocaml:** retain specialized iterator dispatch ([433b9ef](https://github.com/fullofcaffeine/hxhx/commit/433b9ef944b150c866b89a169d5f1ff7c814326d))
* **ocaml:** retain standard map declaration signatures ([9e5b8bc](https://github.com/fullofcaffeine/hxhx/commit/9e5b8bc0708347b7201c167da75d0f4809383160))
* **ocaml:** retain structural signatures for recursive modules ([b12ca20](https://github.com/fullofcaffeine/hxhx/commit/b12ca20d3bc24fa0afe1e60ac9313bfc0fa75d15))
* **ocaml:** retain typed arrays in enum payloads ([2bb8072](https://github.com/fullofcaffeine/hxhx/commit/2bb8072ebc8a1cf3a4bb5a686992886f806c1613))
* **ocaml:** retain typed generic method captures ([22a28bc](https://github.com/fullofcaffeine/hxhx/commit/22a28bc1c863640995e4756ec159b6de1528a6d8))
* **ocaml:** retire stale array-buffer output rewriting ([571d7be](https://github.com/fullofcaffeine/hxhx/commit/571d7be9ef2894108ccb9c2b43f4b4d97a069b4f))
* **ocaml:** return enum constants through runtime descriptors ([3123d64](https://github.com/fullofcaffeine/hxhx/commit/3123d641839a58ebe29bbc130cca3d14b2c8f025))
* **ocaml:** reuse nullable storage for macro enum arguments ([b1fe4ab](https://github.com/fullofcaffeine/hxhx/commit/b1fe4ab2917ad9d63b2edd717f48c25c33b5ea7a))
* **ocaml:** select authored exception providers ([3da56d0](https://github.com/fullofcaffeine/hxhx/commit/3da56d0b84976cd2c2fe45b34a2bfd4ca235b82f))
* **ocaml:** separate the shared literal carrier type ([f67f0f3](https://github.com/fullofcaffeine/hxhx/commit/f67f0f33ead2b578df85484469f0fb11dddc7782))
* **ocaml:** share typed callback conversions in native emission ([cd27dc4](https://github.com/fullofcaffeine/hxhx/commit/cd27dc4c73332720f151275d89ce0ac12008f005))
* **ocaml:** validate optional representation metadata with null safety ([048389c](https://github.com/fullofcaffeine/hxhx/commit/048389c79b5966ef2caa970b77c93812e9a08781))
* **parser:** accept try expressions in assignment operands ([99fa7a2](https://github.com/fullofcaffeine/hxhx/commit/99fa7a2112b1d06a10dc49efdc91a1e891695424))
* **parser:** attach annotations to the whole grouped value ([0506ca9](https://github.com/fullofcaffeine/hxhx/commit/0506ca98c03d262da8b6225f18056d2e58bc7edd))
* **parser:** bound value-block source at its closing brace ([68cf16b](https://github.com/fullofcaffeine/hxhx/commit/68cf16b1a80277b72f40bfd936a061bc01b030c0))
* **parser:** distinguish final classes from module fields ([5f81288](https://github.com/fullofcaffeine/hxhx/commit/5f81288e4a363967f9de4f42d6964359f3718af5))
* **parser:** distinguish native dollar names from macro splices ([96f3eef](https://github.com/fullofcaffeine/hxhx/commit/96f3eef8b36ffa617c2efd664f28b7d8057ec74c))
* **parser:** end braced functions before following expressions ([5c91866](https://github.com/fullofcaffeine/hxhx/commit/5c918663073f9f371edcb93b6965ebf00364691d))
* **parser:** preserve authored abstract header metadata ([64f31de](https://github.com/fullofcaffeine/hxhx/commit/64f31debba55e31ff0d26a24d0b3a698d168a325))
* **parser:** preserve call-expression function bodies ([ab7b1c0](https://github.com/fullofcaffeine/hxhx/commit/ab7b1c004b1025ec807f464b056653074c087c78))
* **parser:** preserve keywords in stored try expressions ([a12eaa2](https://github.com/fullofcaffeine/hxhx/commit/a12eaa2af7b0182020af0a9a9318d48d5638427d))
* **parser:** preserve original class source positions ([033a6d2](https://github.com/fullofcaffeine/hxhx/commit/033a6d285c11a3ae11787431b6b78a591df0f9f5))
* **parser:** retain brace-terminated local function returns ([a325aa0](https://github.com/fullofcaffeine/hxhx/commit/a325aa07077c9e5faaa88f0167590136f4cd88c4))
* **parser:** retain enum-abstract method bodies ([1639db4](https://github.com/fullofcaffeine/hxhx/commit/1639db4178cbbb70ad91bde9f57baf4c4df966fa))
* **parser:** retain exact token end positions ([7808a16](https://github.com/fullofcaffeine/hxhx/commit/7808a164cacfbfe27d4e54aaaaa493e7b2ebc63d))
* **parser:** retain generic local function syntax ([a7499df](https://github.com/fullofcaffeine/hxhx/commit/a7499dfdff57882b288347358fbaa6842a9d4d4b))
* **parser:** separate body metadata from return hints ([962ee9e](https://github.com/fullofcaffeine/hxhx/commit/962ee9e20c4296b3c07d88916c8913739e4a060a))
* **php:** consume exact runtime type operands ([426e597](https://github.com/fullofcaffeine/hxhx/commit/426e597cfd551207223a6f06a842d7c220074555))
* **php:** preserve Boolean console output ([239defd](https://github.com/fullofcaffeine/hxhx/commit/239defd86671d0e16fc4c2400fb9d659b57da07c))
* **python:** admit library static calls only when Python implements them ([4d8e04b](https://github.com/fullofcaffeine/hxhx/commit/4d8e04b38c4ebcb7bf4186fb505e8c4917a06f12))
* **python:** execute typed initializers and expression functions ([8e54df4](https://github.com/fullofcaffeine/hxhx/commit/8e54df43072c1f8113aa527e5ba31ed051669fcd))
* **python:** keep admitted Type and Reflect helpers faithful to upstream ([b128f45](https://github.com/fullofcaffeine/hxhx/commit/b128f459ae5cf2ebc2e220bc3625de286b6100b9))
* **python:** map exact constructors to emitted classes ([74b1d27](https://github.com/fullofcaffeine/hxhx/commit/74b1d2751b8f5e102fe0282d6d01b74be9199cf2))
* **python:** preserve Boolean text in Std.string ([36e2799](https://github.com/fullofcaffeine/hxhx/commit/36e2799334435b7cc974a8e7b48476ec81faaaa3))
* **python:** preserve entry-class static members ([46baf51](https://github.com/fullofcaffeine/hxhx/commit/46baf51205ac338d1b979f7020699bc3b1d2fb90))
* **python:** reject class values the Python target cannot honor ([3bf1a98](https://github.com/fullofcaffeine/hxhx/commit/3bf1a982f41a5808c15ebf361682399fd211f24d))
* **python:** report full Haxe class paths from Type.getClassName ([cff8414](https://github.com/fullofcaffeine/hxhx/commit/cff8414cdca8ea02de80d9c1eb4794dd693bdd0a))
* **python:** retain static field declaration owners ([ea12864](https://github.com/fullofcaffeine/hxhx/commit/ea12864c491216b38da5ab8c4670ded19154422a))
* **python:** use emitted classes for static owners ([4602d16](https://github.com/fullofcaffeine/hxhx/commit/4602d16ff04f948dcb23af7fd17743bc07cc46df))
* **reports:** make lowering digests portable across hosts ([e3fbf0b](https://github.com/fullofcaffeine/hxhx/commit/e3fbf0b46e0936e3540ed1aa50ed64313ad580eb))
* **resolver:** ignore comments during module discovery ([2a08394](https://github.com/fullofcaffeine/hxhx/commit/2a08394c27342eb32d7259aa54616b47ad480b5e))
* **server:** audit and clear retained emitter state early ([b6da0ac](https://github.com/fullofcaffeine/hxhx/commit/b6da0ac90aa9968e431f33987141b59dd2a1b300))
* **snapshots:** isolate compiler input during updates ([c56b145](https://github.com/fullofcaffeine/hxhx/commit/c56b1453c5212a63ab7b8da1ff0720e3e03cd06b))
* **snapshots:** support scoped golden updates ([d97afdd](https://github.com/fullofcaffeine/hxhx/commit/d97afddf5ac9fdcf852d1fb12e85c15b498d96c2))
* **source:** discover helpers behind selected static calls ([9fdecc4](https://github.com/fullofcaffeine/hxhx/commit/9fdecc4a02954c79233b0fe58209ea1eb49c5e1d))
* **stage3:** fail closed on missing call arguments ([cf1548f](https://github.com/fullofcaffeine/hxhx/commit/cf1548f1a551cab5ef67ec72021d52951ad88148))
* **stage3:** select locals through exact typed projections ([28c9149](https://github.com/fullofcaffeine/hxhx/commit/28c9149bb29b5412e03459cb40713ac04124d7d2))
* **targets:** preserve typed uninitialized Java and C# locals ([fa27b0b](https://github.com/fullofcaffeine/hxhx/commit/fa27b0b550030ec3e412faf9c0d0069dafff77ba))
* **test:** include production providers in Neko fixtures ([0e58df0](https://github.com/fullofcaffeine/hxhx/commit/0e58df03add92d324627df8c89371022ca72f988))
* **test:** select Dynamic return emission modes explicitly ([5620ebc](https://github.com/fullofcaffeine/hxhx/commit/5620ebcf0bc971403168b3bc9dd951846940d860))
* **tests:** isolate snapshot updater from caller paths ([bb45238](https://github.com/fullofcaffeine/hxhx/commit/bb45238c55ea4ea42f656a7335f63eb92daa51aa))
* **test:** use standard tools for recursive module checks ([2430ee8](https://github.com/fullofcaffeine/hxhx/commit/2430ee8fe45b86c3aafff19743145daa6938a884))
* **tooling:** attribute bootstrap resources to server workers ([ccc5273](https://github.com/fullofcaffeine/hxhx/commit/ccc52737c51a470c98a4b0e7eaa6d4d07089e2f1))
* **tooling:** close the server startup interruption gap ([ecd5327](https://github.com/fullofcaffeine/hxhx/commit/ecd532700d021d41279a50a6df534963c794e9cc))
* **tooling:** coordinate native macro-host builds ([8c222dd](https://github.com/fullofcaffeine/hxhx/commit/8c222dded3294c2bdc3b2bfdd02c5ac4670f49e7))
* **tooling:** expose live source-build phase progress ([6ee05ba](https://github.com/fullofcaffeine/hxhx/commit/6ee05ba788c6cda7322a7ccb0c081779071aaa0f))
* **tooling:** measure bootstrap watchdog elapsed time ([79ce65a](https://github.com/fullofcaffeine/hxhx/commit/79ce65aba772e435481b8c6857b272852ef55fbc))
* **tooling:** monitor connected bootstrap server ([b0fe51c](https://github.com/fullofcaffeine/hxhx/commit/b0fe51c66030be171f51de4bc15c943cc2ce917a))
* **tooling:** preserve changed formatter output and lifecycle ([ec6af46](https://github.com/fullofcaffeine/hxhx/commit/ec6af46524cc1099153978f2a77408bcdcbc9e91))
* **tooling:** preserve ownership checks during interrupted startup ([888b400](https://github.com/fullofcaffeine/hxhx/commit/888b400d1792107e5d8a368010ff415263e46966))
* **tooling:** retain observed Haxe server children ([59dd4e6](https://github.com/fullofcaffeine/hxhx/commit/59dd4e6393b098162d312d3035acd197b421d50a))
* **tooling:** stop builds after source emission failures ([a97fe2f](https://github.com/fullofcaffeine/hxhx/commit/a97fe2f47811f40b346045c34e75bf6ff551d923))
* **typer:** accept enum values in generic constraints ([89a7bdc](https://github.com/fullofcaffeine/hxhx/commit/89a7bdcd5b82974dd91eb5f4fea8dd4fca746ec5))
* **typer:** accept equivalent recursive record views ([4552e84](https://github.com/fullofcaffeine/hxhx/commit/4552e84738479dd2b21e6d2088d0e34fb9344eea))
* **typer:** admit partial values at Dynamic boundaries ([2837d7c](https://github.com/fullofcaffeine/hxhx/commit/2837d7cd2b26da750c51a8b20a8060864654e385))
* **typer:** admit solved Dynamic call arguments ([e0bf064](https://github.com/fullofcaffeine/hxhx/commit/e0bf064913dff15f801759b770a784c5e29b34a1))
* **typer:** apply generic abstract header conversions ([a17046a](https://github.com/fullofcaffeine/hxhx/commit/a17046a1cb782304c4b39145bd57314ba4e72c90))
* **typer:** apply parameter context to function values ([cfe3c01](https://github.com/fullofcaffeine/hxhx/commit/cfe3c01408a071694e376a92e6f794fdba340214))
* **typer:** check property signatures by assignment direction ([b15f998](https://github.com/fullofcaffeine/hxhx/commit/b15f9983e2c0219fd3e8283ce1f910ecf66a478b))
* **typer:** constrain nested arrays in record arguments ([8315c9d](https://github.com/fullofcaffeine/hxhx/commit/8315c9d07b4092a0c68261ed8f589c12512d5944))
* **typer:** contextualize constructor arguments ([426bc28](https://github.com/fullofcaffeine/hxhx/commit/426bc288f999345a7da29607fe9d139efbbd72fd))
* **typer:** convert omitted inputs at callback destinations ([5598e85](https://github.com/fullofcaffeine/hxhx/commit/5598e851122c9423db41f016f763739597755fbe))
* **typer:** convert unresolved inputs at Dynamic uses ([b27219c](https://github.com/fullofcaffeine/hxhx/commit/b27219c7cf031032154d3aee5c8f71b53b9a6481))
* **typer:** exclude parser fallback headers from declarations ([d6ca565](https://github.com/fullofcaffeine/hxhx/commit/d6ca5655396ae835b2ff763f4e9341173e1050e2))
* **typer:** execute authored conversions to Dynamic ([0e331e9](https://github.com/fullofcaffeine/hxhx/commit/0e331e943e984afcfeb07e17a6d31af27b587677))
* **typer:** infer generic structural call arguments ([c2aa95f](https://github.com/fullofcaffeine/hxhx/commit/c2aa95f4f4291d975da48e3e18d116491ccc2add))
* **typer:** infer Int inputs from bitwise operations ([24b1d7d](https://github.com/fullofcaffeine/hxhx/commit/24b1d7d78d15b870281c29843ba9a9e7208415ef))
* **typer:** infer unchecked cast results independently ([450dcfa](https://github.com/fullofcaffeine/hxhx/commit/450dcfa4e3166af5dd4efc9fdd570d3ca310c2ca))
* **typer:** infer values through abstract input headers ([8a5bf36](https://github.com/fullofcaffeine/hxhx/commit/8a5bf36861ca7e24a4a4fb5658a03287293b0380))
* **typer:** keep constructor body completion separate ([e6b8356](https://github.com/fullofcaffeine/hxhx/commit/e6b8356c42d4d865dec8c60f26831c52f25c6fa5))
* **typer:** keep enum operations outside class absence checks ([6d203ca](https://github.com/fullofcaffeine/hxhx/commit/6d203ca452f4f5bc80f523d4586e1e21ef436d6e))
* **typer:** keep unloaded names and Any catches in scope ([0722523](https://github.com/fullofcaffeine/hxhx/commit/0722523f8d0b61d607e5fb4ae362defde953cbd5))
* **typer:** load declarations before provider lookup ([5aa8d92](https://github.com/fullofcaffeine/hxhx/commit/5aa8d92e20718b0bf93a748149ee7c34153afe58))
* **typer:** load standard aliases in declaration scope order ([30f3f0b](https://github.com/fullofcaffeine/hxhx/commit/30f3f0b334854d3dc4502754a4d8b7eaacab73de))
* **typer:** match omitted optional enum pattern payloads ([7e57509](https://github.com/fullofcaffeine/hxhx/commit/7e575099b717c157c4dcdf3fc97391b827ba8148))
* **typer:** prepare lookup candidates before body typing ([15c5f14](https://github.com/fullofcaffeine/hxhx/commit/15c5f14edf071c6e478fd6f4ecf51bc662854a0b))
* **typer:** preserve abstract operator order and conversions ([c78af99](https://github.com/fullofcaffeine/hxhx/commit/c78af997ea85a8a60aa93b34647eb6bc1d23d13b))
* **typer:** preserve authored metadata overload order ([63e4b5a](https://github.com/fullofcaffeine/hxhx/commit/63e4b5af4a4ee47805dd9f3ce3663448a91ec720))
* **typer:** preserve bare wildcard enum pattern suffixes ([288c720](https://github.com/fullofcaffeine/hxhx/commit/288c72082ad7f7796fbf62a636ca49efee2d888a))
* **typer:** preserve comprehension bindings in required inline calls ([e4ad794](https://github.com/fullofcaffeine/hxhx/commit/e4ad7946f86a1abb2a346a22119a4030a08b17e8))
* **typer:** preserve core String receiver values ([ea1abf2](https://github.com/fullofcaffeine/hxhx/commit/ea1abf26bc849222fa388edab39c241abcba1382))
* **typer:** preserve declared bounds at call publication ([7f17341](https://github.com/fullofcaffeine/hxhx/commit/7f173413a9cc7dbdb2f7cd453353eefb72e9baea))
* **typer:** preserve enum constant reads without property storage ([8ae655a](https://github.com/fullofcaffeine/hxhx/commit/8ae655a4f0a7d9cf07d4556b05d8b546e1e1a368))
* **typer:** preserve full-function default parameter types ([85276fa](https://github.com/fullofcaffeine/hxhx/commit/85276fa162ed8bd04057df761a5eb97b09daec2a))
* **typer:** preserve functions from plain module imports ([ac62cee](https://github.com/fullofcaffeine/hxhx/commit/ac62ceef0a43ac89044baaac9178018f5c4e6f1b))
* **typer:** preserve nested generic argument delimiters ([28c7377](https://github.com/fullofcaffeine/hxhx/commit/28c737711fc2829e17ef92d7b0ad154225126e86))
* **typer:** preserve null-coalescing fallback context ([aeec45f](https://github.com/fullofcaffeine/hxhx/commit/aeec45f641683719855fca35059d951040a22728))
* **typer:** preserve omitted inputs at Dynamic call sites ([bb3b2ff](https://github.com/fullofcaffeine/hxhx/commit/bb3b2ff55e389b19734a6c80310a0376c86a463c))
* **typer:** preserve saved interval cursor semantics ([54148ea](https://github.com/fullofcaffeine/hxhx/commit/54148ea77c97465311c0f2a36ee0e6de186f2a46))
* **typer:** preserve static abstract property updates ([f2e76af](https://github.com/fullofcaffeine/hxhx/commit/f2e76af4e92ebc4b8a96be743ebfc880644b3a48))
* **typer:** preserve static abstract qualifiers ([e173a93](https://github.com/fullofcaffeine/hxhx/commit/e173a931b060eca05947327a74c63f7e9009f92b))
* **typer:** preserve structural declarations during resolution ([4612689](https://github.com/fullofcaffeine/hxhx/commit/4612689486f809e87f1872ca5968cda4060be3d8))
* **typer:** preserve typed catch bindings ([13974f6](https://github.com/fullofcaffeine/hxhx/commit/13974f60f9720222e395bb9de8984e543d0aae4b))
* **typer:** preserve unresolved inputs at Dynamic destinations ([1bfae58](https://github.com/fullofcaffeine/hxhx/commit/1bfae58a68cd453b447644a4de6db97c97c51de1))
* **typer:** project nested indexed updates and gate them to JavaScript ([0f5dcd3](https://github.com/fullofcaffeine/hxhx/commit/0f5dcd3feff3f5efea0ec17cbc331b678bfdeed6))
* **typer:** prove forwarded generic constraints by identity ([d767f95](https://github.com/fullofcaffeine/hxhx/commit/d767f9527205faf07e78fb23bc77532794aa4fd1))
* **typer:** publish method-input batches only for filled inputs ([42d1e70](https://github.com/fullofcaffeine/hxhx/commit/42d1e70c1d708989a676dc1003fad65bf724bf91))
* **typer:** reject absent methods on known receivers ([29359d0](https://github.com/fullofcaffeine/hxhx/commit/29359d0e7c819d484c454cd224facf7f509ca316))
* **typer:** resolve enum arguments from expected declarations ([a78f59e](https://github.com/fullofcaffeine/hxhx/commit/a78f59ee74916bb90e915902af17406c684a8b2c))
* **typer:** resolve exact root-qualified type paths ([6fdd4e4](https://github.com/fullofcaffeine/hxhx/commit/6fdd4e4f04f10d36adf894a06b3fd09ddfb77699))
* **typer:** retain abstract static method identities ([b9aba3a](https://github.com/fullofcaffeine/hxhx/commit/b9aba3ad9036ef4334311c6721d74ecb0a6ce888))
* **typer:** retain addition constraints in method inputs ([fd683d9](https://github.com/fullofcaffeine/hxhx/commit/fd683d9e8f9d960428feb75bbba8e1ece72e1498))
* **typer:** retain checked array context during replay ([913f6a0](https://github.com/fullofcaffeine/hxhx/commit/913f6a0b0a1035413b8c5f54b56f3f9cb0c79b74))
* **typer:** retain collection context through call branches ([4c7257d](https://github.com/fullofcaffeine/hxhx/commit/4c7257d860bac6c372c4a6faa94578f531c5cdd6))
* **typer:** retain concrete results across Dynamic try branches ([2cc5aeb](https://github.com/fullofcaffeine/hxhx/commit/2cc5aeb806d5899edc792c8e9aa3a25629fa1897))
* **typer:** retain conditional empty-array inference ([7d86e69](https://github.com/fullofcaffeine/hxhx/commit/7d86e691d26bd1bd0b1c44f8b2b4842784cf5bb7))
* **typer:** retain declared Dynamic results across call constraints ([dc526af](https://github.com/fullofcaffeine/hxhx/commit/dc526affe291c5aaac0b423895bf9bd132028307))
* **typer:** retain declared indexed element contracts ([baedfcf](https://github.com/fullofcaffeine/hxhx/commit/baedfcf80996c8aa57f3796f42e33bee25b0b985))
* **typer:** retain declared Map literal entry types ([20ffb0b](https://github.com/fullofcaffeine/hxhx/commit/20ffb0b7ed38c037d87d119a5244bf5a4c18a933))
* **typer:** retain declared object literal field types ([763c1da](https://github.com/fullofcaffeine/hxhx/commit/763c1da09f838a93b1ceb137e541d517295f39ce))
* **typer:** retain Dynamic call argument context ([e49f1d9](https://github.com/fullofcaffeine/hxhx/commit/e49f1d9d679840b0e49f7695f893004e112061fe))
* **typer:** retain Dynamic evidence for untyped results ([46a9786](https://github.com/fullofcaffeine/hxhx/commit/46a97860a838148a538d6bbc0d829c76f0ce8ac8))
* **typer:** retain expanded bodies for inference replay ([e570f4a](https://github.com/fullofcaffeine/hxhx/commit/e570f4a05794b1f3ccb4cade568013037f903795))
* **typer:** retain extern dynamic member contracts ([f90d983](https://github.com/fullofcaffeine/hxhx/commit/f90d983df81191104c370a0b3423986929f43fb9))
* **typer:** retain inference at generic Dynamic destinations ([89923f9](https://github.com/fullofcaffeine/hxhx/commit/89923f9403a9edf53acab706940f7fa9e9bcfcd3))
* **typer:** retain inference on a local's first assignment ([be9b0ca](https://github.com/fullofcaffeine/hxhx/commit/be9b0ca7965a3cdca639869a6225c8c808d051e1))
* **typer:** retain inferred elements through indexed access ([11a135c](https://github.com/fullofcaffeine/hxhx/commit/11a135cd9bfd40800623a20fe955774ef5380aa5))
* **typer:** retain inferred void results at call sites ([6d8f41a](https://github.com/fullofcaffeine/hxhx/commit/6d8f41a604277b9869da53ddfce28cc78554c86e))
* **typer:** retain inherited Array element types in reads ([7592904](https://github.com/fullofcaffeine/hxhx/commit/7592904c240206f34718a77dffb59c693f1ec272))
* **typer:** retain known inputs for generic callbacks ([b374c61](https://github.com/fullofcaffeine/hxhx/commit/b374c617985366a4ec16833858f98dc12e7ab83b))
* **typer:** retain named bindings when replaying solved functions ([b295356](https://github.com/fullofcaffeine/hxhx/commit/b295356ead142caf79c4e223f0c45f82b3d70cb5))
* **typer:** retain nullable array inference across calls ([77982ce](https://github.com/fullofcaffeine/hxhx/commit/77982ce02885f024dd0357313c2457e296ba3168))
* **typer:** retain nullable structural call compatibility ([4a523df](https://github.com/fullofcaffeine/hxhx/commit/4a523dfe724df73c8947a6b0d1671eb663ccf482))
* **typer:** retain omitted method input evidence ([be3028b](https://github.com/fullofcaffeine/hxhx/commit/be3028b0de368979d4a254d2092e72836e7a225e))
* **typer:** retain primary declarations for extern overloads ([6ce264f](https://github.com/fullofcaffeine/hxhx/commit/6ce264f6892c02c234fc085754baaeadbf5a7ed5))
* **typer:** retain spread arguments in constructor selection ([fdd81c0](https://github.com/fullofcaffeine/hxhx/commit/fdd81c08f197d6491da667e896fdc538840cd67b))
* **typer:** retain types in immediately called lambdas ([5c2bfc6](https://github.com/fullofcaffeine/hxhx/commit/5c2bfc627c4774b50fdaae6e76223582876916bf))
* **typer:** retain unchecked field argument constraints ([ae8671a](https://github.com/fullofcaffeine/hxhx/commit/ae8671af3f440483bd9a7ed2516a423c8c963810))
* **typer:** retain untyped calls through open fields ([66ef0c0](https://github.com/fullofcaffeine/hxhx/commit/66ef0c07b06375426bab6bd6aec8e5a291db8447))
* **typer:** retain untyped indexing without abstract helpers ([e0da517](https://github.com/fullofcaffeine/hxhx/commit/e0da517645125420645758f44ea14fa89f0a6f24))
* **typer:** save read-only abstract receivers during inlining ([d222f32](https://github.com/fullofcaffeine/hxhx/commit/d222f3210efb49efb1f90c2d7a1339b95465c53f))
* **typer:** select declared abstract indexed calls ([0c42153](https://github.com/fullofcaffeine/hxhx/commit/0c4215355f98d30584d864679c4b8613ef0189b4))
* **typer:** select enum constructors from expected results ([811ddab](https://github.com/fullofcaffeine/hxhx/commit/811ddab465d63d23c8b5eca3cc8e2f6ed138e15f))
* **typer:** select helpers for nullable MapCounter indexed updates ([e336eca](https://github.com/fullofcaffeine/hxhx/commit/e336eca019ec798a53de58ca5509de65870c9ad3))
* **typer:** separate nullable indexed update admission ([758bfb0](https://github.com/fullofcaffeine/hxhx/commit/758bfb0e1b6060a44a6e19ea54f1dfdae7338b98))
* **typer:** share receiver inference with call operands ([3804ed9](https://github.com/fullofcaffeine/hxhx/commit/3804ed978fcb87d3944ad897724a3f89b53cb638))
* **typer:** treat full Int enum abstract value switches as exhaustive ([39fe90e](https://github.com/fullofcaffeine/hxhx/commit/39fe90eedc127c40d7c5f1891fefbdc4d0637a42))
* **typer:** type new on bare generic aliases such as Map ([9881bb3](https://github.com/fullofcaffeine/hxhx/commit/9881bb3f5f407652c39cb9a600a27505178a8d8f))
* **typer:** type rest parameters as haxe.Rest in method bodies ([fed91e3](https://github.com/fullofcaffeine/hxhx/commit/fed91e318f6077fd69ff0c1c8348986068bde9ff))
* **typer:** type unexpanded macro calls and abstract to-conversion constructors ([68594df](https://github.com/fullofcaffeine/hxhx/commit/68594df215bbb68108651c66e00d111c7f3a5163))
* **typer:** validate direct generic method constraints ([c1e5e5a](https://github.com/fullofcaffeine/hxhx/commit/c1e5e5a1004c5dd109fd21617562f63f437965de))
* **types:** resolve structural intersection aliases ([bec89bc](https://github.com/fullofcaffeine/hxhx/commit/bec89bcedb8c2f04f8e965bf96f2597b16f4118f))
* **types:** respect structural method parameter scope ([d4cbf1d](https://github.com/fullofcaffeine/hxhx/commit/d4cbf1df3ae7e060a25d608f91284affbd3aa965))
* **typing:** complete source annotation consumers ([1307933](https://github.com/fullofcaffeine/hxhx/commit/130793398964f0f2cfefbfb6d215282dabaa0784))
* **typing:** convert inline receiver assignments before storage views ([4f3529c](https://github.com/fullofcaffeine/hxhx/commit/4f3529cae4e6c3a2c207f9c93a0b4ad839b2170a))
* **typing:** discard disabled trace operands before inference ([e55b944](https://github.com/fullofcaffeine/hxhx/commit/e55b9449c24e77718002b40686eae5ba7668686f))
* **typing:** distinguish source annotations from casts ([f92ec66](https://github.com/fullofcaffeine/hxhx/commit/f92ec66d5ee61d02d63e4334839a81fdcbb6d2a5))
* **typing:** load declaration signature dependencies ([be72804](https://github.com/fullofcaffeine/hxhx/commit/be728046f7a72550600912f0ed98717fdb39f042))
* **typing:** load implicit standard declarations before indexing ([76ff7c5](https://github.com/fullofcaffeine/hxhx/commit/76ff7c5dd4ffadbec517cf8157797d817680959a))
* **typing:** preserve callback context through source blocks ([37e3f40](https://github.com/fullofcaffeine/hxhx/commit/37e3f407630e9483879da8cacd8404603860cf3a))
* **typing:** preserve caller storage in inline unary updates ([8cabeb2](https://github.com/fullofcaffeine/hxhx/commit/8cabeb2b3bf4574d67ac0bd53535c64250d28330))
* **typing:** preserve declared abstract inputs in calls ([d7b3b39](https://github.com/fullofcaffeine/hxhx/commit/d7b3b39f57de2226c635e180b6c193914f9fb07b))
* **typing:** preserve extern interface runtime boundaries ([9850993](https://github.com/fullofcaffeine/hxhx/commit/9850993090124d38ed48b957cd12030947f63169))
* **typing:** preserve null argument evidence at publication ([056a07f](https://github.com/fullofcaffeine/hxhx/commit/056a07f72902708d7c97c23b24e5692acd88165f))
* **typing:** preserve optional and rest parameter entry types ([a84e9a4](https://github.com/fullofcaffeine/hxhx/commit/a84e9a4c886ce52f91dba87f2b4f120dd81185eb))
* **typing:** preserve selected native binary operations ([42ba9b1](https://github.com/fullofcaffeine/hxhx/commit/42ba9b10b2c8f8d12aeea86eba372c80a28cff51))
* **typing:** preserve wildcard witnesses for guarded switches ([d21c88f](https://github.com/fullofcaffeine/hxhx/commit/d21c88f1caaa8ea9c97a6eb05778b59115e5cd1a))
* **typing:** recognize shadowed switch captures in coverage ([bb2147c](https://github.com/fullofcaffeine/hxhx/commit/bb2147cbc4e323db0dd5f9bd823e8902c6dd5ae0))
* **typing:** retain abstract property update storage proof ([3e4e466](https://github.com/fullofcaffeine/hxhx/commit/3e4e466e4eac6a9ca686fbb266a6baf7db6c1253))
* **typing:** retain the selected Array class context ([6ec8a28](https://github.com/fullofcaffeine/hxhx/commit/6ec8a28813172a6f1c6b10a72bebd067e807d0c2))
* **typing:** retain written types in expression initializers ([1f0a5e6](https://github.com/fullofcaffeine/hxhx/commit/1f0a5e64b355eefbd3fb3d6667bb7a250a3c45fd))


### Features

* **compiler:** checkpoint native target integration ([ed1f441](https://github.com/fullofcaffeine/hxhx/commit/ed1f44140275d58b225414825e2ef32a837f9b99)), closes [#92](https://github.com/fullofcaffeine/hxhx/issues/92)
* **core:** retain typed callback facts in body projections ([b3d3cef](https://github.com/fullofcaffeine/hxhx/commit/b3d3cef993db29083183b4cb9dc081401f2b9fce))
* **cpp:** add rooted Dynamic value comparisons ([1fae4a0](https://github.com/fullofcaffeine/hxhx/commit/1fae4a008bd9747eb6cc622bc4a36692521e00a1))
* **cpp:** execute typed carrier catch regions ([883d4e2](https://github.com/fullofcaffeine/hxhx/commit/883d4e23e27eb4a4807617efcd23d99721e7add9))
* **cpp:** preserve authored instance string conversions ([2d18dec](https://github.com/fullofcaffeine/hxhx/commit/2d18deccc090f72b4ccbf46d0fea2b93461243f3))
* **cpp:** preserve enum descriptor values ([7410d66](https://github.com/fullofcaffeine/hxhx/commit/7410d6680e052155d10bb41024858bd3448bd5c7))
* **cpp:** select Boolean exception handlers ([7ce5f22](https://github.com/fullofcaffeine/hxhx/commit/7ce5f2254dd90e489cc47c23e0adc151545d1021))
* **cpp:** support managed type reflection ([6976bdc](https://github.com/fullofcaffeine/hxhx/commit/6976bdc80a9e1dddde74f9bb244a8c047058eac2))
* **hxhx:** select macro declarations before argument typing ([ce6487e](https://github.com/fullofcaffeine/hxhx/commit/ce6487ec7aecc4f211f1197f077a2343ce3624ba))
* **hxhx:** select project macro declarations before typing ([085fdf6](https://github.com/fullofcaffeine/hxhx/commit/085fdf6ee1b8609cbc792bd9ad2b1b8914c0937f))
* **hxhx:** track lexical scope during macro traversal ([7f695f3](https://github.com/fullofcaffeine/hxhx/commit/7f695f345bebf064488281658a2aa46fb19cdf96))
* **js:** lower validated nominal runtime type operands ([95e9542](https://github.com/fullofcaffeine/hxhx/commit/95e9542dac873f2cf3ed580e523ab85a669fa3c9))
* **neko:** index exact typed helper declarations ([92d6d78](https://github.com/fullofcaffeine/hxhx/commit/92d6d7830e33f367cecfa080167e128ecf0f27f9))
* **neko:** match primitive runtime type predicates ([aca5eb4](https://github.com/fullofcaffeine/hxhx/commit/aca5eb4633c6fc15d7d791aa856ac22dd301b8e5))
* **neko:** preserve ordered typed catch dispatch ([5a431de](https://github.com/fullofcaffeine/hxhx/commit/5a431de31e605ab37a60809dd1837d304a1eed96))
* **neko:** retain exact executable catch plans ([676d9dc](https://github.com/fullofcaffeine/hxhx/commit/676d9dc574da16d893a632f0d36683e8f67e648d))
* **neko:** retain exact field initializer ownership ([4bfde1d](https://github.com/fullofcaffeine/hxhx/commit/4bfde1da02aa03deebc14e6bf27cbd4561316bac))
* **neko:** share canonical class objects across output chunks ([9de7289](https://github.com/fullofcaffeine/hxhx/commit/9de7289c2c1a4467f4ba72135e7e09fa3742bdc5))
* **ocaml:** add checked method dispatch storage ([972d418](https://github.com/fullofcaffeine/hxhx/commit/972d418ac282822f71c11629b97e6d38daeade12))
* **ocaml:** add host-neutral binding facts ([70bc297](https://github.com/fullofcaffeine/hxhx/commit/70bc2974c350d87736b506a9e1aeafdf1d461e79))
* **ocaml:** add host-neutral declaration input ([c89391f](https://github.com/fullofcaffeine/hxhx/commit/c89391f8913b4238ef946dfd5c9364e7ecf7e811))
* **ocaml:** add recursive target input tracer ([91bbf23](https://github.com/fullofcaffeine/hxhx/commit/91bbf23683e7a674e76a818074b73d12b3638546))
* **ocaml:** admit native class marker inputs ([76647ec](https://github.com/fullofcaffeine/hxhx/commit/76647ec54b1631a5585fe2e46b168e704b824791))
* **ocaml:** bind callback adapters to local occurrences ([c0add92](https://github.com/fullofcaffeine/hxhx/commit/c0add9222d7c1841013c8afa3ddc167a57967fd5))
* **ocaml:** check function-only recursive module exports ([8572254](https://github.com/fullofcaffeine/hxhx/commit/857225498a2d9ce400881bfaf00c680317870309))
* **ocaml:** classify enum result producers before admission ([20f707a](https://github.com/fullofcaffeine/hxhx/commit/20f707ae583b6688e85a40b34229a326670882f4))
* **ocaml:** classify native callback consumers ([408be7e](https://github.com/fullofcaffeine/hxhx/commit/408be7e5a8481ec511c6f9a243caffb4027907dd))
* **ocaml:** collect structured module references ([0bda71b](https://github.com/fullofcaffeine/hxhx/commit/0bda71bedbf89c2b9e32ed65602964ca7dd5576e))
* **ocaml:** define callable view syntax operations ([15eb277](https://github.com/fullofcaffeine/hxhx/commit/15eb2771cbce53780f155f3c6aeffed69b8553aa))
* **ocaml:** describe native enum variant carriers ([a9b6d8f](https://github.com/fullofcaffeine/hxhx/commit/a9b6d8f0e70972befe4f868a5427e5c1d8366ef6))
* **ocaml:** emit function-only recursive module groups ([e96ffe0](https://github.com/fullofcaffeine/hxhx/commit/e96ffe0fbc3a95c270a865dc01e506f4d12f1864))
* **ocaml:** encode typed callback adapter reports ([dca8364](https://github.com/fullofcaffeine/hxhx/commit/dca8364807780e03df061eefefe58a7aa195e4be))
* **ocaml:** execute checked nominal type predicates ([3ddbdda](https://github.com/fullofcaffeine/hxhx/commit/3ddbdda681740107aace2036970e6546c0a26eff))
* **ocaml:** hard-cut literal facts ([b1c9e71](https://github.com/fullofcaffeine/hxhx/commit/b1c9e719ac5cbcc6577711807b8ce8ca68db7e16))
* **ocaml:** hard-cut native hxhx to shared target ([6f1d48f](https://github.com/fullofcaffeine/hxhx/commit/6f1d48f52ccd6a9e250642f2c83baa406c4e92b7))
* **ocaml:** plan deterministic module dependency groups ([184dce2](https://github.com/fullofcaffeine/hxhx/commit/184dce213b98f6163003190fb5616a67bc447b53))
* **ocaml:** preserve identity for closed callback locals ([4716f9e](https://github.com/fullofcaffeine/hxhx/commit/4716f9e92fdfee33a445bbb81a80d4145da38c8b))
* **ocaml:** preserve lazy conditional values in shared target ([c241fb2](https://github.com/fullofcaffeine/hxhx/commit/c241fb2d7d946438a0522ee952e7503b49fd4ccf))
* **ocaml:** preserve nullable integers in shared target programs ([8543365](https://github.com/fullofcaffeine/hxhx/commit/85433655782081c0236fc57f7515aca0a8b594bd))
* **ocaml:** preserve represented static function signatures ([ec574e7](https://github.com/fullofcaffeine/hxhx/commit/ec574e78369773d2f1e29263c7466ef7f058e232))
* **ocaml:** preserve shared functions through preprocessing ([f6039ab](https://github.com/fullofcaffeine/hxhx/commit/f6039ab2c248bab07d8c533fe08069087cabee31))
* **ocaml:** register closed callback view layouts ([bcafd59](https://github.com/fullofcaffeine/hxhx/commit/bcafd598225c50331d59f3c3efe111e24d861e27))
* **ocaml:** retain callback producers in local write plans ([ce0102b](https://github.com/fullofcaffeine/hxhx/commit/ce0102b7d23c2e15366dd00f811f0686dcd8dbed))
* **ocaml:** route exact field expressions through shared target ([b0842c1](https://github.com/fullofcaffeine/hxhx/commit/b0842c1f738090d39dd3c12ade92a287f2686570))
* **ocaml:** select callback identity from typed producers ([cf42807](https://github.com/fullofcaffeine/hxhx/commit/cf428070640b171cec4fd6b401ae242c1550db82))
* **ocaml:** select typed callback view conversions ([f324398](https://github.com/fullofcaffeine/hxhx/commit/f324398d63a79d72fef588053d8b6be5405312d2))
* **ocaml:** share function parameters and returned values ([e33dcdc](https://github.com/fullofcaffeine/hxhx/commit/e33dcdc9a8af8a10539b6a693e52e7a92b275f60))
* **ocaml:** share instance method bodies across compiler hosts ([dbda362](https://github.com/fullofcaffeine/hxhx/commit/dbda362b42b19c569216f02f951da67b76ec2e40))
* **ocaml:** share ordered comparisons and lazy Boolean operations ([5a39af4](https://github.com/fullofcaffeine/hxhx/commit/5a39af4bee894bdf016a9c0aa2fd905115d6217f))
* **ocaml:** share resolved static Void calls ([b4a017b](https://github.com/fullofcaffeine/hxhx/commit/b4a017bc319599ecdabb1b6322cd972812bebf7c))
* **ocaml:** share resolved static Void calls ([#49](https://github.com/fullofcaffeine/hxhx/issues/49)) ([1ce9825](https://github.com/fullofcaffeine/hxhx/commit/1ce98252edd826026d4acbe8082a46e498514f50))
* **parser:** preserve parentheses as structural syntax ([154f53d](https://github.com/fullofcaffeine/hxhx/commit/154f53da4c17714bbf49dfadb8dd42bbcaedcd2d))
* **python:** lower runtime type checks from typed occurrences ([019c314](https://github.com/fullofcaffeine/hxhx/commit/019c314a69f8033547c33b0b66b67acffa2dc6c0))
* **typer:** add atomic indexed-update trials ([3b9c449](https://github.com/fullofcaffeine/hxhx/commit/3b9c449bdd23d9a11921d24551dd0b33b6907f7d))
* **typer:** add isolated generic inference solver ([f741d03](https://github.com/fullofcaffeine/hxhx/commit/f741d03ca200944d7f018f8cb739cd7b7275407e))
* **typer:** admit and project declared abstract indexed updates ([2766a2e](https://github.com/fullofcaffeine/hxhx/commit/2766a2e409a8b7d92551f43585ab77c197eb0a4f))
* **typer:** preserve primitive runtime type values ([caeb6ad](https://github.com/fullofcaffeine/hxhx/commit/caeb6ad903c1514a8d17199266be36a4e1bd3c2e))
* **typer:** resolve inherited generic receiver arguments ([d419616](https://github.com/fullofcaffeine/hxhx/commit/d419616e30ea5b98f20864ec8f909a6e4c97d675))
* **typer:** retain abstract backing types in backend facts ([fa6b79c](https://github.com/fullofcaffeine/hxhx/commit/fa6b79c2eb619bd5902edaabd302693706bc90c6))
* **typer:** retain checked indexed update helper results ([cfecca8](https://github.com/fullofcaffeine/hxhx/commit/cfecca8f9f1677f77407e5cadfc4c8a7eb70d2c3))
* **typer:** retain declaration-resolved generic bounds ([28cfe51](https://github.com/fullofcaffeine/hxhx/commit/28cfe51e976ce58482faade1084daf3ed0998fe8))
* **typer:** retain public reflection names ([2b4c687](https://github.com/fullofcaffeine/hxhx/commit/2b4c68780c64f909117b41cb03914edd7d7f9bbb))
* **typing:** admit explicit Array and String runtime targets ([c4bd840](https://github.com/fullofcaffeine/hxhx/commit/c4bd8407e5485d542dc6862cd1fc2a671401dd3d))
* **typing:** check directly resolved enum abstract switches ([b79dadd](https://github.com/fullofcaffeine/hxhx/commit/b79daddaede034740380e6157dfc374933d1d187))
* **typing:** retain exact runtime type operands through projection ([cc50b4a](https://github.com/fullofcaffeine/hxhx/commit/cc50b4a4fecaed2da9d9dd74db955b46a178a5c7))
* **typing:** retain interface inheritance in shared class facts ([e49fc04](https://github.com/fullofcaffeine/hxhx/commit/e49fc04472c57c048d4b03ef6159170264fa701b))


### Performance Improvements

* **ci:** start independent tests alongside guardrails ([60c57ab](https://github.com/fullofcaffeine/hxhx/commit/60c57ab5841533931b424b24652b69661dae7c23))
* **cpp:** bound repeated program validation ([2185fbf](https://github.com/fullofcaffeine/hxhx/commit/2185fbfd60cd2d3b3f58e097865fa32649f5bb42))
* **cpp:** extract duplicated field-call fallback bodies ([6689693](https://github.com/fullofcaffeine/hxhx/commit/66896939d792281c35ea1644f4c3be492d9be259))
* **ocaml:** avoid discarded operand rendering ([346f34a](https://github.com/fullofcaffeine/hxhx/commit/346f34a76cd97e207e281822a06a5a5e42b5de61))
* **ocaml:** avoid hashing identical representation selections ([e26c675](https://github.com/fullofcaffeine/hxhx/commit/e26c6754d7100cbd4a3e10984926d0a1b65d1141))
* **ocaml:** avoid materializing scalar callees during selection ([bda97ee](https://github.com/fullofcaffeine/hxhx/commit/bda97ee50553584ac1f7419f6e728b956158ed74))
* **ocaml:** bound repeated recursive native-surface queries ([191010e](https://github.com/fullofcaffeine/hxhx/commit/191010ee24625993ee918cb014d3b337ad917753))
* **ocaml:** limit preliminary lookups to call expressions ([71e0c7f](https://github.com/fullofcaffeine/hxhx/commit/71e0c7f9d060d94de37b9359c2d35398158c510e))
* **ocaml:** narrow null flow before array-read validation ([e0166cf](https://github.com/fullofcaffeine/hxhx/commit/e0166cf79d4caad996fa488e8ae143e08cbaeeac))
* **ocaml:** reject data fields before receiver inspection ([9b904c0](https://github.com/fullofcaffeine/hxhx/commit/9b904c039e495d4cb79cc0920d146f420e24600a))
* **ocaml:** reject impossible method-view sources early ([476b817](https://github.com/fullofcaffeine/hxhx/commit/476b817fbff4a3284995bb5f2f23ec326cdd7f07))
* **ocaml:** reuse completed native-type checks within bodies ([15cf791](https://github.com/fullofcaffeine/hxhx/commit/15cf791207cb7b6f73c6c3eab356286b6462c675))
* **ocaml:** skip implementation hash when reuse is disabled ([dbc1cf8](https://github.com/fullofcaffeine/hxhx/commit/dbc1cf83bc6f56a6340d394755f6db30df567d57))
* **ocaml:** validate copied structures once during plan construction ([45f5554](https://github.com/fullofcaffeine/hxhx/commit/45f55542001dcb8f8da4cf858214cf0e9859526b))
* **reflaxe:** avoid duplicate lifecycle scans ([6d77fb3](https://github.com/fullofcaffeine/hxhx/commit/6d77fb306dbda33b6aac1a76fc6892d794a8329b))
* **reflaxe:** combine strict native-surface scans ([91fbd43](https://github.com/fullofcaffeine/hxhx/commit/91fbd43f58d8421a130b79993a3080c174e340b2))
* **reflaxe:** defer byte occurrence hashing ([19f5a3c](https://github.com/fullofcaffeine/hxhx/commit/19f5a3ca8f423bcdd6cdef06728e554997f8d42c))
* **reflaxe:** expose interrupted function preparation ([1c795b4](https://github.com/fullofcaffeine/hxhx/commit/1c795b44bc2a9d6c68dde28650b530b046389c88))
* **reflaxe:** reuse preliminary call decisions ([1f861fd](https://github.com/fullofcaffeine/hxhx/commit/1f861fd93600d8d24e463671ae822d0180af0a99))
* **reflaxe:** reuse root revision for nested plans ([2d44c2c](https://github.com/fullofcaffeine/hxhx/commit/2d44c2cbb171741211ebab21c95d5c6b5d207aed))
* **test:** compile nullable-return inspector once ([b99d31e](https://github.com/fullofcaffeine/hxhx/commit/b99d31e0c289cc50a1720aff4dc3d58b74198f35))
* **test:** compile the inheritance inspector once ([d914b5b](https://github.com/fullofcaffeine/hxhx/commit/d914b5b86ceb17d241096843798c060434778620))
* **test:** parallelize isolated golden updates ([79b9191](https://github.com/fullofcaffeine/hxhx/commit/79b9191ee4ef1528e7d3342daf93aa6cfe7b1193))
* **tooling:** batch bootstrap input checksums ([ae17e85](https://github.com/fullofcaffeine/hxhx/commit/ae17e857bc2cd5b3096da67a2ee7e0c767acd90e)), closes [#55](https://github.com/fullofcaffeine/hxhx/issues/55)
* **tooling:** use native SHA-256 for Neko reports ([b72ba8f](https://github.com/fullofcaffeine/hxhx/commit/b72ba8f2207aaac915331ab44e6635526ce2d0d3))
* **typing:** read each expression tag once during validation ([497f354](https://github.com/fullofcaffeine/hxhx/commit/497f354e3308252616d597666ab05b90137ef797))

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
