const requireNoCache = require("./requireNoCache");
const config = requireNoCache("../deploy-configs/get-network-config");

module.exports = async ({ web3, getNamedAccounts, deployments, artifacts }) => {
  const { deploy, log, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployResult = await deploy("xMPH", {
    from: deployer,
    proxy: {
      owner: config.govTimelock,
      proxyContract: "OptimizedTransparentProxy"
    },
    log: true
  });
  if (deployResult.newlyDeployed) {
    const xMPH = artifacts.require("xMPH");
    const contract = await xMPH.at(deployResult.address);
    const MPHToken = artifacts.require("MPHToken");
    const mphAddress = config.isEthereum
      ? config.mph
      : (await get("MPHToken")).address;
    const mphContract = await MPHToken.at(mphAddress);
    await mphContract.approve(deployResult.address, 1e9);
    await contract.initialize(
      mphAddress,
      config.xMPHRewardUnlockPeriod,
      config.govTreasury
    );

    // transfer xMPH ownership to gov treasury
    const DEFAULT_ADMIN_ROLE = "0x00";
    const DISTRIBUTOR_ROLE = web3.utils.soliditySha3("DISTRIBUTOR_ROLE");
    await contract.grantRole(DEFAULT_ADMIN_ROLE, config.govTreasury, {
      from: deployer
    });
    log(`Give xMPH DEFAULT_ADMIN_ROLE to ${config.govTreasury}`);

    // renounce xMPH admin role
    await contract.renounceRole(DEFAULT_ADMIN_ROLE, deployer, {
      from: deployer
    });
    log(`Renounce xMPH DEFAULT_ADMIN_ROLE of ${deployer}`);
  }
};
module.exports.tags = ["xMPH"];
module.exports.dependencies = config.isEthereum ? [] : ["MPHToken"];
