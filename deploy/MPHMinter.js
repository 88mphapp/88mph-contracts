const BigNumber = require("bignumber.js");
const requireNoCache = require("./requireNoCache");
const config = requireNoCache("../deploy-configs/get-network-config");

module.exports = async ({ web3, getNamedAccounts, deployments, artifacts }) => {
  const { deploy, log, get, execute, read } = deployments;
  const { deployer } = await getNamedAccounts();

  const vesting02Deployment = await get("Vesting02");

  const mphAddress = config.isEthereum
    ? config.mph
    : (await get("MPHToken")).address;
  const deployResult = await deploy("MPHMinter", {
    from: deployer,
    contract: "MPHMinter",
    log: true,
    proxy: {
      owner: config.govTimelock,
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [
            mphAddress,
            config.govTreasury,
            config.devWallet,
            vesting02Deployment.address,
            BigNumber(config.devRewardMultiplier).toFixed(),
            BigNumber(config.govRewardMultiplier).toFixed(),
          ],
        },
      },
    },
  });

  // set MPHMinter address for Vesting02
  if ((await read("Vesting02", "mphMinter")) !== deployResult.address) {
    await execute(
      "Vesting02",
      { from: deployer },
      "setMPHMinter",
      deployResult.address
    );
    log(`Set MPHMinter in Vesting02 to ${deployResult.address}`);
  }

  // transfer Vesting02 ownership to gov treasury
  if ((await read("Vesting02", "owner")) !== config.govTreasury) {
    await execute(
      "Vesting02",
      { from: deployer },
      "transferOwnership",
      config.govTreasury,
      true,
      false
    );
    log(`Transfer Vesting02 ownership to ${config.govTreasury}`);
  }

  // Transfer MPHToken ownership to MPHMinter
  if ((await read("MPHToken", "owner")) !== deployResult.address) {
    await execute(
      "MPHToken",
      { from: deployer },
      "transferOwnership",
      deployResult.address
    );
    log(`Transfer MPHToken ownership to ${deployResult.address}`);
  }
};
module.exports.tags = ["MPHMinter"];
module.exports.dependencies = config.isEthereum
  ? ["Vesting02"]
  : ["Vesting02", "MPHToken"];
