const BigNumber = require('bignumber.js')

module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log, get } = deployments
  const { deployer } = await getNamedAccounts()

  const templateDeployment = await get('ZeroCouponBondTemplate')
  const fractionalDepositFactoryDeployment = await get('FractionalDepositFactory')
  const deployResult = await deploy('ZeroCouponBondFactory', {
    from: deployer,
    args: [
      templateDeployment.address,
      fractionalDepositFactoryDeployment.address
    ]
  })
  if (deployResult.newlyDeployed) {
    log(`ZeroCouponBondFactory deployed at ${deployResult.address}`)
  }
}
module.exports.tags = ['ZeroCouponBondFactory']
module.exports.dependencies = ['ZeroCouponBondTemplate', 'FractionalDepositFactory']
