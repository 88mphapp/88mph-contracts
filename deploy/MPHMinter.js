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
            BigNumber(config.govRewardMultiplier).toFixed()
          ]
        }
      }
    }
  });
  if (deployResult.newlyDeployed) {
    log(`MPHMinter deployed at ${deployResult.address}`);
  }

  // give roles to gov treasury
  const DEFAULT_ADMIN_ROLE =
    "0x0000000000000000000000000000000000000000000000000000000000000000";
  const WHITELISTER_ROLE = web3.utils.soliditySha3("WHITELISTER_ROLE");
  /*if (
    !(await read(
      "MPHMinter",
      "hasRole",
      DEFAULT_ADMIN_ROLE,
      config.govTreasury
    ))
  ) {
    await execute(
      "MPHMinter",
      { from: deployer },
      "grantRole",
      DEFAULT_ADMIN_ROLE,
      config.govTreasury
    );
    log(`Grant MPHMinter DEFAULT_ADMIN_ROLE to ${config.govTreasury}`);
  }
  if (
    !(await read("MPHMinter", "hasRole", WHITELISTER_ROLE, config.govTreasury))
  ) {
    await execute(
      "MPHMinter",
      { from: deployer },
      "grantRole",
      WHITELISTER_ROLE,
      config.govTreasury
    );
    log(`Grant MPHMinter WHITELISTER_ROLE to ${config.govTreasury}`);
  }
  if (await read("MPHMinter", "hasRole", DEFAULT_ADMIN_ROLE, deployer)) {
    await execute(
      "MPHMinter",
      { from: deployer },
      "renounceRole",
      DEFAULT_ADMIN_ROLE,
      deployer
    );
    log(`Renounce MPHMinter DEFAULT_ADMIN_ROLE of ${deployer}`);
  }*/

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
