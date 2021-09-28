const requireNoCache = require("./requireNoCache");
const config = requireNoCache("../deploy-configs/get-network-config");
const poolConfig = requireNoCache("../deploy-configs/get-pool-config");

const nftName = `${poolConfig.nftNamePrefix}Deposit`;
const nftSymbol = `${poolConfig.nftSymbolPrefix}Deposit`;

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { log, deploy, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const nftDescriptorDeployment = await get("NFTDescriptor");

  const deployResult = await deploy(nftName, {
    from: deployer,
    contract: "NFTWithSVG",
    libraries: {
      NFTDescriptor: nftDescriptorDeployment.address
    },
    proxy: {
      owner: config.govTimelock,
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [nftName, nftSymbol]
        }
      }
    }
  });

  if (deployResult.newlyDeployed) {
    log(`${nftName} deployed at ${deployResult.address}`);
  }
};
module.exports.tags = [nftName, "DepositNFT"];
module.exports.dependencies = ["NFTDescriptor"];
