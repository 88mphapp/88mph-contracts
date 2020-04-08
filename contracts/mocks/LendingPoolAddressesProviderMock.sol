pragma solidity 0.6.5;

contract LendingPoolAddressesProviderMock {
    address internal pool;

    function getLendingPool() external view returns (address) {
        return pool;
    }

    function setLendingPoolImpl(address _pool) external {
        pool = _pool;
    }
}