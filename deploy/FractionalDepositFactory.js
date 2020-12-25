const BigNumber = require('bignumber.js')

module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log, get } = deployments
  const { deployer } = await getNamedAccounts()
  const config = require('../deploy-configs/get-network-config')

  const templateDeployment = await get('FractionalDepositTemplate')
  const deployResult = await deploy('FractionalDepositFactory', {
    from: deployer,
    args: [
      templateDeployment.address,
      config.mph
    ]
  })
  if (deployResult.newlyDeployed) {
    log(`FractionalDepositFactory deployed at ${deployResult.address}`)
  }
}
module.exports.tags = ['FractionalDepositFactory']
module.exports.dependencies = ['FractionalDepositTemplate']
