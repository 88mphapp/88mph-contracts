const config = require('../deploy-configs/get-network-config')
const poolConfig = require('../deploy-configs/get-pool-config')

module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { log, get } = deployments
  const { deployer } = await getNamedAccounts()

  // transfer MPHMinter ownership to gov treasury
  const mphMinterDeployment = await get('MPHMinter')
  const MPHMinter = artifacts.require('MPHMinter')
  const mphMinterContract = await MPHMinter.at(mphMinterDeployment.address)
  await mphMinterContract.transferOwnership(config.govTreasury, { from: deployer })
  log(`Transfer MPHMinter ownership to ${config.govTreasury}`)

  // transfer MPHIssuanceModel ownership to gov treasury
  const mphIssuanceModelDeployment = await get(config.mphIssuanceModel)
  const MPHIssuanceModel = artifacts.require(config.mphIssuanceModel)
  const mphIssuanceModelContract = await MPHIssuanceModel.at(mphIssuanceModelDeployment.address)
  await mphIssuanceModelContract.transferOwnership(config.govTreasury, { from: deployer })
  log(`Transfer MPHIssuanceModel ownership to ${config.govTreasury}`)

  // transfer Rewards ownership to gov treasury
  const rewardsDeployment = await get('Rewards')
  const Rewards = artifacts.require('Rewards')
  const rewardsContract = await Rewards.at(rewardsDeployment.address)
  await rewardsContract.transferOwnership(config.govTreasury, { from: deployer })
  log(`Transfer Rewards ownership to ${config.govTreasury}`)

  // Transfer FeeModel ownership to gov
  const feeModelDeployment = await get(poolConfig.feeModel)
  const FeeModel = artifacts.require(poolConfig.feeModel)
  const feeModelContract = await FeeModel.at(feeModelDeployment.address)
  await feeModelContract.transferOwnership(config.govTreasury, { from: deployer })
  log(`Transfer ${poolConfig.feeModel} ownership to ${config.govTreasury}`)
}
module.exports.tags = ['transfer-ownerships']
module.exports.dependencies = ['MPHMinter', config.mphIssuanceModel, 'Rewards', poolConfig.feeModel]
module.exports.runAtTheEnd = true
