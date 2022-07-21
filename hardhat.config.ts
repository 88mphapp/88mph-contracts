import "@nomiclabs/hardhat-truffle5";
import "@nomiclabs/hardhat-web3";
import "solidity-coverage";
import "hardhat-deploy";
import "hardhat-gas-reporter";
import "@nomiclabs/hardhat-solhint";
import "hardhat-spdx-license-identifier";
import "hardhat-docgen";
import "@nomiclabs/hardhat-etherscan";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-contract-sizer";
import "@typechain/hardhat";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-waffle";

import { HardhatUserConfig } from "hardhat/config";

let secret;

try {
  secret = require("./secret.json");
} catch {
  secret = "";
}

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.4",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
      /*, debug: {
        revertStrings: "strip"
      }*/
    }
  },
  namedAccounts: {
    deployer: {
      default: 0
    }
  },
  paths: {
    sources: "./contracts"
  },
  networks: {
    hardhat: {
      forking: {
        url: "https://eth-mainnet.g.alchemy.com/v2/pvGDp1uf8J7QZ7MXpLhYs_SnMnsE0TY5"
      },
      accounts: [{
        privateKey: secret,
        balance: 100e18.toString()
      }]
    },
    mainnet: {
      url: "https://eth-mainnet.g.alchemy.com/v2/pvGDp1uf8J7QZ7MXpLhYs_SnMnsE0TY5",
      chainId: 1,
      accounts: [secret]
    },
    rinkeby: {
      url:
        "https://eth-rinkeby.alchemyapi.io/v2/2LxgvUYd5FzgiXVoAWlq-KyM4v-E7KJ4",
      chainId: 4,
      accounts: [secret]
    },
    polygon: {
      url: "https://polygon-rpc.com",
      chainId: 137,
      accounts: [secret],
      gasPrice: 3.5e9
    },
    avalanche: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      chainId: 43114,
      accounts: [secret]
    },
    fantom: {
      url: "https://rpc.ftm.tools",
      chainId: 250,
      accounts: [secret]
    }
  },
  spdxLicenseIdentifier: {
    runOnCompile: true
  },
  docgen: {
    except: ["^contracts/mocks/", "^contracts/*.?/imports/"],
    clear: true,
    runOnCompile: false
  },
  mocha: {
    timeout: 60000
  },
  etherscan: {
    apiKey: "SCTNNP3MJK18WV84QIX6WPGMWIS8H1J9W7"
  },
  gasReporter: {
    currency: "USD",
    coinmarketcap: "b0c64afd-6aca-4201-8779-db8dc03e9793"
  },
  typechain: {
    target: "ethers-v5"
  }
};

export default config;
