const requireNoCache = require("./requireNoCache");
const config = requireNoCache("../deploy-configs/get-network-config");
const BigNumber = require("bignumber.js");

module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log, get, execute, read } = deployments;
  const { deployer } = await getNamedAccounts();

  const feeRecipient = config.isEthereum
    ? (await get("Dumper")).address
    : config.govTreasury;

  const deployResult = await deploy("PercentageFeeModel", {
    from: deployer,
    args: [
      feeRecipient,
      BigNumber(config.interestFee).toFixed(),
      BigNumber(config.earlyWithdrawFee).toFixed()
    ]
  });
  if (deployResult.newlyDeployed) {
    log(`PercentageFeeModel deployed at ${deployResult.address}`);
  }

  // Transfer FeeModel ownership to gov treasury
  if ((await read("PercentageFeeModel", "owner")) !== config.govTreasury) {
    await execute(
      "PercentageFeeModel",
      { from: deployer },
      "transferOwnership",
      config.govTreasury
    );
    log(`Transfer PercentageFeeModel ownership to ${config.govTreasury}`);
  }
};
module.exports.tags = ["PercentageFeeModel"];
module.exports.dependencies = config.isEthereum ? ["Dumper"] : [];
