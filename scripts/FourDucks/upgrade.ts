import { ethers, upgrades } from "hardhat";

async function main() {
  const chainId = (await ethers.provider.getNetwork()).chainId;
  console.log("Chain ID:", chainId);
  const gas = await ethers.provider.getGasPrice();
  console.log("Gas price:", gas.toString());
  const FourDucks = await ethers.getContractFactory("FourDucks");
  console.log("Upgrade to FourDucks...");
  const fourDucks = await upgrades.upgradeProxy(
    "",
    FourDucks
  );
  console.log("FourDucks proxy deployed to:", fourDucks.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
