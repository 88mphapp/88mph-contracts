const config = require("../deploy-configs/get-network-config");

module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const xMPHDeployment = await get("xMPH");

  const deployResult = await deploy("Dumper", {
    from: deployer,
    contract: "Dumper",
    args: [config.oneSplitAddress, xMPHDeployment.address]
  });
  if (deployResult.newlyDeployed) {
    log(`Dumper deployed at ${deployResult.address}`);

    // give Dumper DISTRIBUTOR_ROLE in xMPH
    const DISTRIBUTOR_ROLE = web3.utils.soliditySha3("DISTRIBUTOR_ROLE");
    const xMPH = artifacts.require("xMPH");
    const xMPHContract = await xMPH.at(xMPHDeployment.address);
    await xMPHContract.grantRole(DISTRIBUTOR_ROLE, deployResult.address, {
      from: deployer
    });

    // give admin role to gov treasury and revoke deployer's admin role
    const DEFAULT_ADMIN_ROLE = "0x00";
    const Dumper = artifacts.require("Dumper");
    const dumperContract = await Dumper.at(deployResult.address);
    await dumperContract.grantRole(DEFAULT_ADMIN_ROLE, config.govTreasury, {
      from: deployer
    });
    await dumperContract.revokeRole(DEFAULT_ADMIN_ROLE, deployer, {
      from: deployer
    });
  }
};
module.exports.tags = ["Dumper", "MPHRewards"];
module.exports.dependencies = ["xMPH"];
