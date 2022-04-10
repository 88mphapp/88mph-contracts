const fs = require("fs");
const { readdir, readFile } = require("fs/promises");

const excludedNetworks = ["rinkeby"];

/**
 * @dev Outputs a list of all interest oracle addresses for each deployed network
 * Usage: in the project root directory, use `node scripts/output-oracles.js`
 * The result will be sent to stdout
 */

async function main() {
  // read list of networks
  let networkList = [];
  try {
    networkList = await readdir("./deployments/");
  } catch (err) {
    throw err;
  }
  networkList = networkList.filter((n) => !excludedNetworks.includes(n));

  // add oracles for each network
  let result = {};
  for (const network of networkList) {
    let oracleAddresses = [];
    let oracleFileNameList;

    // get all oracle deployment file names
    try {
      oracleFileNameList = await readdir(`./deployments/${network}`);
    } catch (err) {
      throw err;
    }
    oracleFileNameList = oracleFileNameList.filter(
      (f) => f.includes("88mph") && f.includes("EMAOracle")
    );

    // read all oracle addresses of network
    for (const oracleFileName of oracleFileNameList) {
      // read in deployment object
      let deploymentObject;
      try {
        deploymentObject = JSON.parse(
          await readFile(`./deployments/${network}/${oracleFileName}`)
        );
      } catch (err) {
        throw err;
      }

      // push address to network oracle list
      oracleAddresses.push(deploymentObject.address);
    }

    // add network oracle address list to result
    result[network] = oracleAddresses;
  }

  // send result to stdout
  console.log(JSON.stringify(result));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
