const poolConfig = require('../deploy-configs/get-pool-config')

const nftName = `${poolConfig.nftNamePrefix}Bond`
const nftSymbol = `${poolConfig.nftSymbolPrefix}Bond`

module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log } = deployments
  const { deployer } = await getNamedAccounts()

  const deployResult = await deploy(nftName, {
    from: deployer,
    contract: 'NFT',
    args: [
      nftName,
      nftSymbol
    ]
  })
  if (deployResult.newlyDeployed) {
    log(`${nftName} deployed at ${deployResult.address}`)
  }
}
module.exports.tags = [nftName]
module.exports.dependencies = []
