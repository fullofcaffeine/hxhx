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
