# fucking infura always tells me my transaction is underpriced
# just retry until deployment succeeds
if [ $# -eq 0 ]; then
    # use local hardhat network
    npx hardhat run scripts/multideploy.js
    while [ $? -ne 0 ]; do
        npx hardhat run scripts/multideploy.js
    done
else
    # deploy to live network
    npx hardhat run scripts/multideploy.js --network $1
    while [ $? -ne 0 ]; do
        npx hardhat run scripts/multideploy.js --network $1
    done
fi
