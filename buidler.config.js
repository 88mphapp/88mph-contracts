usePlugin('@nomiclabs/buidler-truffle5')
usePlugin('solidity-coverage')
usePlugin('buidler-deploy')

let secret

try {
  secret = require('./secret.json')
} catch {
  secret = {
    account: '',
    mnemonic: ''
  }
}

module.exports = {
  solc: {
    version: '0.5.17',
    optimizer: {
      enabled: true,
      runs: 200
    }
  },
  namedAccounts: {
    deployer: {
      default: 1
    }
  },
  paths: {
    sources: './contracts'
  },
  networks: {
    mainnet: {
      url: 'https://eth-mainnet.alchemyapi.io/v2/pvGDp1uf8J7QZ7MXpLhYs_SnMnsE0TY5',
      chainId: 1,
      from: secret.account,
      accounts: {
        mnemonic: secret.mnemonic
      },
      gas: 'auto',
      gasPrice: 24.0000001e9
    },
    buidlerevm: {
      blockGasLimit: 9950000,
      gas: 'auto',
      gasPrice: 'auto'
    },
    ganache: {
      url: 'http://localhost:8545',
      gas: 'auto',
      gasPrice: 24.0000001e9
    }
  }
}
