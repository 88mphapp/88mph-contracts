// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {
    ClonesUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import {
    StringsUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import {ERC1155Upgradeable} from "./ERC1155Upgradeable.sol";
import {ERC1155Base} from "./ERC1155Base.sol";
import {ERC20Wrapper} from "./ERC20Wrapper.sol";

/**
    @notice An ERC-1155 multitoken where each ID is wrapped in an ERC-20 interface
 */
abstract contract WrappedERC1155Token is ERC1155Base {
    using ClonesUpgradeable for address;
    using StringsUpgradeable for uint256;

    mapping(uint256 => address) public tokenIDToWrapper;
    address public wrapperTemplate;
    bool public deployWrapperOnMint;
    string public baseName;
    string public baseSymbol;
    uint8 public decimals;

    function __WrappedERC1155Token_init(
        address admin,
        string memory uri,
        address _wrapperTemplate,
        bool _deployWrapperOnMint,
        string memory _baseName,
        string memory _baseSymbol,
        uint8 _decimals
    ) internal initializer {
        __ERC1155Base_init(admin, uri);
        __WrappedERC1155Token_init_unchained(
            _wrapperTemplate,
            _deployWrapperOnMint,
            _baseName,
            _baseSymbol,
            _decimals
        );
    }

    function __WrappedERC1155Token_init_unchained(
        address _wrapperTemplate,
        bool _deployWrapperOnMint,
        string memory _baseName,
        string memory _baseSymbol,
        uint8 _decimals
    ) internal initializer {
        wrapperTemplate = _wrapperTemplate;
        deployWrapperOnMint = _deployWrapperOnMint;
        baseName = _baseName;
        baseSymbol = _baseSymbol;
        decimals = _decimals;
    }

    /**
        @notice Called by an ERC20Wrapper contract to handle a transfer call.
        @dev Only callable by a wrapper deployed by this contract.
        @param from Source of transfer
        @param to Target of transfer
        @param tokenID The ERC-1155 token ID of the wrapper
        @param amount The amount to transfer
     */
    function wrapperTransfer(
        address from,
        address to,
        uint256 tokenID,
        uint256 amount
    ) external {
        require(
            msg.sender == tokenIDToWrapper[tokenID],
            "WrappedERC1155Token: not wrapper"
        );
        _safeTransferFrom(from, to, tokenID, amount, bytes(""));
    }

    /**
        @notice Deploys an ERC20Wrapper contract for the ERC-1155 tokens with ID `tokenID`.
        @dev If a wrapper already exists for this tokenID, does nothing and returns the address
             of the existing wrapper.
        @param tokenID The ID of the token to wrap
        @return wrapperAddress The address of the wrapper
     */
    function deployWrapper(uint256 tokenID)
        external
        returns (address wrapperAddress)
    {
        return _deployWrapper(tokenID);
    }

    /**
        @dev See {deployWrapper}
     */
    function _deployWrapper(uint256 tokenID)
        internal
        returns (address wrapperAddress)
    {
        wrapperAddress = tokenIDToWrapper[tokenID];
        if (wrapperAddress == address(0)) {
            // deploy wrapper
            ERC20Wrapper wrapper = ERC20Wrapper(wrapperTemplate.clone());
            string memory tokenIDString = tokenID.toString();
            string memory name =
                string(abi.encodePacked(baseName, tokenIDString));
            string memory symbol =
                string(abi.encodePacked(baseSymbol, tokenIDString));
            wrapper.initialize(address(this), tokenID, name, symbol, decimals);
            tokenIDToWrapper[tokenID] = address(wrapper);
        }
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

        if (from == address(0)) {
            // Mint
            if (deployWrapperOnMint) {
                for (uint256 i = 0; i < ids.length; i++) {
                    _deployWrapper(ids[i]);
                }
            }
        }

        // Emit transfer event in wrapper
        for (uint256 i = 0; i < ids.length; i++) {
            address wrapperAddress = tokenIDToWrapper[ids[i]];
            if (wrapperAddress != address(0)) {
                ERC20Wrapper wrapper = ERC20Wrapper(wrapperAddress);
                wrapper.emitTransferEvent(from, to, amounts[i]);
            }
        }
    }

    /**
        @dev See {ERC1155Upgradeable._shouldSkipSafeTransferAcceptanceCheck}
     */
    function _shouldSkipSafeTransferAcceptanceCheck(
        address operator,
        address, /*from*/
        address, /*to*/
        uint256 id,
        uint256, /*amount*/
        bytes memory /*data*/
    ) internal virtual override(ERC1155Upgradeable) returns (bool) {
        address wrapperAddress = tokenIDToWrapper[id];
        if (wrapperAddress != address(0)) {
            // has wrapper, check if operator is the wrapper
            return operator == wrapperAddress;
        } else {
            // no wrapper, should do safety checks
            return false;
        }
    }

    /**
        Param setters (need metadata role)
     */
    function setDeployWrapperOnMint(bool newValue) external {
        require(
            hasRole(METADATA_ROLE, msg.sender),
            "WrappedERC1155Token: no metadata role"
        );
        deployWrapperOnMint = newValue;
    }

    function setBaseName(string calldata newValue) external {
        require(
            hasRole(METADATA_ROLE, msg.sender),
            "WrappedERC1155Token: no metadata role"
        );
        baseName = newValue;
    }

    function setBaseSymbol(string calldata newValue) external {
        require(
            hasRole(METADATA_ROLE, msg.sender),
            "WrappedERC1155Token: no metadata role"
        );
        baseSymbol = newValue;
    }

    uint256[44] private __gap;
}
