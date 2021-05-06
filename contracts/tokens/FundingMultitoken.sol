// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {ERC1155Upgradeable} from "../libs/ERC1155Upgradeable.sol";
import {ERC1155DividendToken} from "../libs/ERC1155DividendToken.sol";
import {WrappedERC1155Token} from "../libs/WrappedERC1155Token.sol";

contract FundingMultitoken is ERC1155DividendToken, WrappedERC1155Token {
    bytes32 public constant DIVIDEND_ROLE = keccak256("DIVIDEND_ROLE");

    function __FundingMultitoken_init(
        address admin,
        string calldata uri,
        address[] memory dividendTokens,
        address _wrapperTemplate,
        bool _deployWrapperOnMint,
        string memory _baseName,
        string memory _baseSymbol,
        uint8 _decimals
    ) internal initializer {
        __ERC1155Base_init(admin, uri);
        __ERC1155DividendToken_init_unchained(dividendTokens);
        __WrappedERC1155Token_init_unchained(
            _wrapperTemplate,
            _deployWrapperOnMint,
            _baseName,
            _baseSymbol,
            _decimals
        );
        __FundingMultitoken_init_unchained(admin);
    }

    function __FundingMultitoken_init_unchained(address admin)
        internal
        initializer
    {
        // DIVIDEND_ROLE is managed by itself
        _setupRole(DIVIDEND_ROLE, admin);
        _setRoleAdmin(DIVIDEND_ROLE, DIVIDEND_ROLE);
    }

    function initialize(
        address admin,
        string calldata uri,
        address[] calldata dividendTokens,
        address _wrapperTemplate,
        bool _deployWrapperOnMint,
        string memory _baseName,
        string memory _baseSymbol,
        uint8 _decimals
    ) external virtual initializer {
        __FundingMultitoken_init(
            admin,
            uri,
            dividendTokens,
            _wrapperTemplate,
            _deployWrapperOnMint,
            _baseName,
            _baseSymbol,
            _decimals
        );
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
            hasRole(DIVIDEND_ROLE, _msgSender()),
            "FundingMultitoken: must have dividend role"
        );
        _registerDividendToken(dividendToken);
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override(ERC1155DividendToken, WrappedERC1155Token) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    /**
        @dev See {ERC1155Upgradeable._shouldSkipSafeTransferAcceptanceCheck}
     */
    function _shouldSkipSafeTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    )
        internal
        override(ERC1155Upgradeable, WrappedERC1155Token)
        returns (bool)
    {
        return
            WrappedERC1155Token._shouldSkipSafeTransferAcceptanceCheck(
                operator,
                from,
                to,
                id,
                amount,
                data
            );
    }

    uint256[50] private __gap;
}
