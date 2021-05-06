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

    const DISTRIBUTOR_ROLE = web3.utils.soliditySha3("DISTRIBUTOR_ROLE");
    const DEFAULT_ADMIN_ROLE = "0x00";

    // give dumper admin role to gov treasury and revoke deployer's admin role
    const Dumper = artifacts.require("Dumper");
    const dumperContract = await Dumper.at(deployResult.address);
    await dumperContract.grantRole(DEFAULT_ADMIN_ROLE, config.govTreasury, {
      from: deployer
    });
    log(`Grant Dumper DEFAULT_ADMIN_ROLE to ${config.govTreasury}`);
    await dumperContract.renounceRole(DEFAULT_ADMIN_ROLE, deployer, {
      from: deployer
    });
    log(`Renounce Dumper DEFAULT_ADMIN_ROLE of ${deployer}`);

    // give Dumper DISTRIBUTOR_ROLE in xMPH
    const xMPH = artifacts.require("xMPH");
    const xMPHContract = await xMPH.at(xMPHDeployment.address);
    await xMPHContract.grantRole(DISTRIBUTOR_ROLE, deployResult.address, {
      from: deployer
    });
    log(`Grant xMPH DISTRIBUTOR_ROLE to ${deployResult.address}`);
  }
};
module.exports.tags = ["Dumper", "MPHRewards"];
module.exports.dependencies = ["xMPH"];
