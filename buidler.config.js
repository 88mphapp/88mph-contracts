usePlugin("@nomiclabs/buidler-truffle5");

let secret;

try {
  secret = require('./secret.json');
} catch {
  secret = {
    account: "",
    mnemonic: ""
  };
}

module.exports = {
  solc: {
    version: "0.5.17",
    optimizer: {
      enabled: true,
      runs: 200
    }
  },
  paths: {
    sources: "./contracts",
  },
  networks: {
    mainnet: {
      url: "https://mainnet.infura.io/v3/7a7dd3472294438eab040845d03c215c",
      chainId: 1,
      from: secret.account,
      accounts: {
        mnemonic: secret.mnemonic
      }
    }
  }
};