const poolConfig = require('../deploy-configs/get-pool-config')

const nftName = `${poolConfig.nftNamePrefix}Deposit`
const nftSymbol = `${poolConfig.nftSymbolPrefix}Deposit`

module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { log, get, getOrNull, save } = deployments
  const { deployer } = await getNamedAccounts()

  const NFTFactoryDeployment = await get('NFTFactory')
  const NFTFactory = artifacts.require('NFTFactory')
  const NFTFactoryContract = await NFTFactory.at(NFTFactoryDeployment.address)

  const NFTDeployment = await getOrNull(nftName)
  if (!NFTDeployment) {
    const deployReceipt = await NFTFactoryContract.createClone(
      nftName,
      nftSymbol,
      { from: deployer }
    )
    const txReceipt = deployReceipt.receipt
    const NFTAddress = txReceipt.logs[0].args._clone
    const NFT = artifacts.require('NFT')
    const NFTContract = await NFT.at(NFTAddress)
    await save(nftName, { abi: NFTContract.abi, address: NFTAddress, receipt: deployReceipt })
    log(`${nftName} deployed at ${NFTAddress}`)
  }
}
module.exports.tags = [nftName]
module.exports.dependencies = ['NFTFactory']
