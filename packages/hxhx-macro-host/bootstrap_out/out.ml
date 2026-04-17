# 1 "out.ml"
let () =
  HxType.set_registry_init_hook HxTypeRegistry.init;
  ignore (Hxhxmacrohost_Main.main ())
