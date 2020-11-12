module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log, get } = deployments
  const { deployer } = await getNamedAccounts()
  const poolConfig = require('../deploy-configs/get-pool-config')
  const compoundConfig = require('../deploy-configs/protocols/compound.json')

  const dumperDeployment = await get('Dumper')

  const deployResult = await deploy('CompoundERC20Market', {
    from: deployer,
    args: [
      poolConfig.moneyMarketParams.cToken,
      compoundConfig.comptroller,
      dumperDeployment.address,
      poolConfig.stablecoin
    ]
  })
  if (deployResult.newlyDeployed) {
    log(`CompoundERC20Market deployed at ${deployResult.address}`)
  }
}
module.exports.tags = ['CompoundERC20Market']
module.exports.dependencies = ['Dumper']
