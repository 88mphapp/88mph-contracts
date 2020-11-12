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
      url: 'https://mainnet.infura.io/v3/7a7dd3472294438eab040845d03c215c',
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
      gasLimit: 1e7,
      gasPrice: 1e11
    }
  }
}
