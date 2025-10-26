
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const PYTH_ADDRESS = "0xDd24F84d36BF92C65F92307595335bdFab5Bbd21";
const AAVE_POOL_ADDRESS = "0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951";

const ETHLockerModule = buildModule("ETHLockerModule", (m) => {
  const nft = m.contract("ETHLockerNFT");

  const ethLocker = m.contract("ETHLocker", [
    PYTH_ADDRESS,
    nft,
    AAVE_POOL_ADDRESS,
  ]);

  m.call(nft, "setMinter", [ethLocker]);

  return { ethLocker, nft };
});

export default ETHLockerModule;
