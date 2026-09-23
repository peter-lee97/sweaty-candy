import { matchHandler, rpcCreateRoom } from "./match.js";

function InitModule(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, initializer: nkruntime.Initializer): void {
  initializer.registerRpc("create_room", rpcCreateRoom);
  initializer.registerMatch("sweaty_candy", matchHandler);
  logger.info("Sweaty Candy Nakama runtime loaded");
}

(globalThis as any).InitModule = InitModule;
