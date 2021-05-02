// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "./ERC1155DividendToken.sol";

contract FundingMultitoken is ERC1155DividendToken {
    bytes32 public constant DIVIDEND_ROLE = keccak256("DIVIDEND_ROLE");

    function __FundingMultitoken_init(
        address[] memory dividendTokens,
        address admin,
        string memory uri
    ) internal initializer {
        __ERC1155DividendToken_init(dividendTokens, admin, uri);
        __FundingMultitoken_init_unchained();
    }

    function __FundingMultitoken_init_unchained() internal initializer {}

    function initialize(
        address[] calldata dividendTokens,
        address admin,
        string calldata uri
    ) external virtual initializer {
        __FundingMultitoken_init(dividendTokens, admin, uri);
    }

    function distributeDividends(
        uint256 tokenID,
        address dividendToken,
        uint256 amount
    ) external {
        require(
            hasRole(DIVIDEND_ROLE, _msgSender()),
            "FundingMultitoken: must have dividend role"
        );
        _distributeDividends(tokenID, dividendToken, amount);
    }

    function withdrawDividend(uint256 tokenID, address dividendToken) external {
        _withdrawDividend(tokenID, dividendToken, msg.sender);
    }

    function withdrawDividendFor(
        uint256 tokenID,
        address dividendToken,
        address user
    ) external {
        require(
            hasRole(DIVIDEND_ROLE, _msgSender()),
            "FundingMultitoken: must have dividend role"
        );
        _withdrawDividend(tokenID, dividendToken, user);
    }

    function registerDividendToken(address dividendToken) external {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "FundingMultitoken: must have admin role"
        );
        _registerDividendToken(dividendToken);
    }

    uint256[50] private __gap;
}
