const BigNumber = require('bignumber.js')

module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log } = deployments
  const { deployer } = await getNamedAccounts()

  const deployResult = await deploy('FractionalDepositTemplate', {
    from: deployer,
    contract: 'FractionalDeposit'
  })
  if (deployResult.newlyDeployed) {
    log(`FractionalDepositTemplate deployed at ${deployResult.address}`)
  }
}
module.exports.tags = ['FractionalDepositTemplate']
module.exports.dependencies = []
