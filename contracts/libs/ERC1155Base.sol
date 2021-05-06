// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {ERC1155Upgradeable} from "./ERC1155Upgradeable.sol";
import {
    AccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/**
    @notice An extension of ERC1155 that provides access-controlled minting and burning,
            as well as a total supply getter for each token ID.
 */
abstract contract ERC1155Base is ERC1155Upgradeable, AccessControlUpgradeable {
    bytes32 public constant MINTER_BURNER_ROLE =
        keccak256("MINTER_BURNER_ROLE");
    bytes32 public constant METADATA_ROLE = keccak256("METADATA_ROLE");
    bytes internal constant NULL_BYTES = bytes("");

    mapping(uint256 => uint256) private _totalSupply;

    function __ERC1155Base_init(address admin, string memory uri)
        internal
        initializer
    {
        __ERC1155_init(uri);
        __ERC1155Base_init_unchained(admin);
    }

    function __ERC1155Base_init_unchained(address admin) internal initializer {
        // admin is granted metadata role and minter-burner role
        // metadata role is managed by itself
        // minter-burner role is managed by itself
        _setupRole(METADATA_ROLE, admin);
        _setupRole(MINTER_BURNER_ROLE, admin);
        _setRoleAdmin(METADATA_ROLE, METADATA_ROLE);
        _setRoleAdmin(MINTER_BURNER_ROLE, MINTER_BURNER_ROLE);
    }

    function mint(
        address to,
        uint256 id,
        uint256 amount
    ) external {
        require(
            hasRole(MINTER_BURNER_ROLE, _msgSender()),
            "ERC1155Base: must have minter-burner role to mint"
        );

        _mint(to, id, amount, NULL_BYTES);
    }

    function mintBatch(
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external {
        require(
            hasRole(MINTER_BURNER_ROLE, _msgSender()),
            "ERC1155Base: must have minter-burner role to mint"
        );

        _mintBatch(to, ids, amounts, NULL_BYTES);
    }

    function burn(
        address account,
        uint256 id,
        uint256 amount
    ) external {
        require(
            hasRole(MINTER_BURNER_ROLE, _msgSender()),
            "ERC1155Base: must have minter-burner role to burn"
        );

        _burn(account, id, amount);
    }

    function burnBatch(
        address account,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external {
        require(
            hasRole(MINTER_BURNER_ROLE, _msgSender()),
            "ERC1155Base: must have minter-burner role to burn"
        );

        _burnBatch(account, ids, amounts);
    }

    function setURI(string calldata newuri) external {
        require(
            hasRole(METADATA_ROLE, _msgSender()),
            "ERC1155Base: must have metadata role to set URI"
        );

        _setURI(newuri);
    }

    function totalSupply(uint256 id) public view returns (uint256) {
        return _totalSupply[id];
    }

    function totalSupplyBatch(uint256[] calldata ids)
        external
        view
        returns (uint256[] memory totalSupplies)
    {
        totalSupplies = new uint256[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            totalSupplies[i] = _totalSupply[ids[i]];
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override(ERC1155Upgradeable) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

        if (from == address(0)) {
            // Mint
            for (uint256 i = 0; i < ids.length; i++) {
                _totalSupply[ids[i]] += amounts[i];
            }
        } else if (to == address(0)) {
            // Burn
            for (uint256 i = 0; i < ids.length; i++) {
                _totalSupply[ids[i]] -= amounts[i];
            }
        }
    }

    uint256[49] private __gap;
}
