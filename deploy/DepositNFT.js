const poolConfig = require('../deploy-configs/pool.json')

const nftName = `${poolConfig.nftNamePrefix}Deposit`
const nftSymbol = `${poolConfig.nftSymbolPrefix}Deposit`

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
module.exports.tags = [nftName, 'DInterestPool']
module.exports.dependencies = []
