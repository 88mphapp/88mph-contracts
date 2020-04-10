pragma solidity 0.6.5;

contract LendingPoolAddressesProviderMock {
    address internal pool;
    address internal core;

    function getLendingPool() external view returns (address) {
        return pool;
    }

    function setLendingPoolImpl(address _pool) external {
        pool = _pool;
    }

    function getLendingPoolCore() external view returns (address) {
        return core;
    }

    function setLendingPoolCoreImpl(address _pool) external {
        core = _pool;
    }
}