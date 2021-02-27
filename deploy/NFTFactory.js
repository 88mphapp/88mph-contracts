const BigNumber = require('bignumber.js')

module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log, get } = deployments
  const { deployer } = await getNamedAccounts()

  const templateDeployment = await get('NFTTemplate')
  const deployResult = await deploy('NFTFactory', {
    from: deployer,
    args: [
      templateDeployment.address
    ]
  })
  if (deployResult.newlyDeployed) {
    log(`NFTFactory deployed at ${deployResult.address}`)
  }
}
module.exports.tags = ['NFTFactory']
module.exports.dependencies = ['NFTTemplate']
