// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "./ERC1155DividendToken.sol";

contract FundingMultitoken is ERC1155DividendToken {
    bytes32 public constant DIVIDEND_ROLE = keccak256("DIVIDEND_ROLE");

    function __FundingMultitoken_init(
        address targetAddress,
        address admin,
        string memory uri
    ) internal initializer {
        __ERC1155DividendToken_init(targetAddress, admin, uri);
        __FundingMultitoken_init_unchained();
    }

    function __FundingMultitoken_init_unchained() internal initializer {}

    function init(
        address targetAddress,
        address admin,
        string calldata uri
    ) external virtual initializer {
        __FundingMultitoken_init(targetAddress, admin, uri);
    }

    function distributeDividends(uint256 tokenID, uint256 amount) external {
        require(
            hasRole(DIVIDEND_ROLE, _msgSender()),
            "FundingMultitoken: must have dividend role"
        );
        _distributeDividends(tokenID, amount);
    }

    function withdrawDividend(uint256 tokenID, address user) external {
        _withdrawDividend(tokenID, user);
    }
}
