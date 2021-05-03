// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

contract LendingPoolAddressesProviderMock {
    address internal pool;
    address internal core;

    function getLendingPool() external view returns (address) {
        return pool;
    }

    function setLendingPoolImpl(address _pool) external {
        pool = _pool;
    }
}
