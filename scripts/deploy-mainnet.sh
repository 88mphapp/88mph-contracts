# fucking infura always tells me my transaction is underpriced
# just retry until deployment succeeds
npx hardhat run scripts/deploy-mainnet.js --network mainnet
while [ $? -ne 0 ]; do
    npx hardhat run scripts/deploy-mainnet.js --network mainnet
done