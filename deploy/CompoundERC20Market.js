module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log, get } = deployments
  const { deployer } = await getNamedAccounts()
  const poolConfig = require('../deploy-configs/get-pool-config')
  const compoundConfig = require('../deploy-configs/protocols/compound.json')

  const rewardsDeployment = await get('Rewards')

  const deployResult = await deploy('CompoundERC20Market', {
    from: deployer,
    args: [
      compoundConfig.cToken,
      compoundConfig.comptroller,
      rewardsDeployment.address,
      poolConfig.stablecoin
    ]
  })
  if (deployResult.newlyDeployed) {
    log(`CompoundERC20Market deployed at ${deployResult.address}`)
  }
}
module.exports.tags = ['CompoundERC20Market']
module.exports.dependencies = ['Rewards']