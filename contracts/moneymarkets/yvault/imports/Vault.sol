// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

interface Vault {
    function deposit(uint256 amount) external;

    function withdraw(uint256 shareAmount) external returns (uint256);

    function withdraw(uint256 shareAmount, address recipient)
        external
        returns (uint256);

    function pricePerShare() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}
