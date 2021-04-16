// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "./ERC1155Base.sol";

contract DepositMultitoken is ERC1155Base {
    function __DepositMultitoken_init(address admin, string memory uri)
        internal
        initializer
    {
        __ERC1155Base_init(admin, uri);
    }

    function init(address admin, string calldata uri)
        external
        virtual
        initializer
    {
        __DepositMultitoken_init(admin, uri);
    }
}
