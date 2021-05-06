const config = require("../deploy-configs/get-network-config");
const BigNumber = require("bignumber.js");

module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const dumperDeployment = await get("Dumper");

  const deployResult = await deploy("PercentageFeeModel", {
    from: deployer,
    args: [
      dumperDeployment.address,
      BigNumber(config.interestFee).toFixed(),
      BigNumber(config.earlyWithdrawFee).toFixed()
    ]
  });
  if (deployResult.newlyDeployed) {
    log(`PercentageFeeModel deployed at ${deployResult.address}`);

    // Transfer FeeModel ownership to gov treasury
    const FeeModel = artifacts.require("PercentageFeeModel");
    const feeModelContract = await FeeModel.at(deployResult.address);
    await feeModelContract.transferOwnership(config.govTreasury, {
      from: deployer
    });
    log(`Transfer PercentageFeeModel ownership to ${config.govTreasury}`);
  }
};
module.exports.tags = ["PercentageFeeModel"];
module.exports.dependencies = ["Dumper"];
