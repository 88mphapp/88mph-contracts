// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

contract AaveV3PoolAddressesProviderMock {
    address internal pool;
    address internal core;

    function getPool() external view returns (address) {
        return pool;
    }

    function setPoolImpl(address _pool) external {
        pool = _pool;
    }
}
