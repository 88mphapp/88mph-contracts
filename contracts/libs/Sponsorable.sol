// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SafeERC20} from "./SafeERC20.sol";

/**
    @notice Add support for meta-txs that use ERC20 tokens to pay for gas
 */
abstract contract Sponsorable {
    using SafeERC20 for IERC20;

    /**
        @dev Using uint256 for all numbers since this struct won't ever be in storage. This saves gas.
        @param sender The user who made the meta-tx
        @param sponsor The account that should receive the sponsor fee
        @param sponsorFeeToken The ERC20 token address the sponsor fee is paid in
        @param sponsorFeeAmount The amount of sponsor fee to transfer from `sender` to `sponsor`
        @param nonce The signature nonce used for preventing replay attacks. Should equal accountNonce[sender].
        @param deadline The timestamp after which the signature is invalid
        @param v ECDSA signature component: Parity of the `y` coordinate of point `R`
        @param r ECDSA signature component: x-coordinate of `R`
        @param s ECDSA signature component: `s` value of the signature
     */
    struct Sponsorship {
        address sender;
        address sponsor;
        address sponsorFeeToken;
        uint256 sponsorFeeAmount;
        uint256 nonce;
        uint256 deadline;
        uint256 v;
        bytes32 r;
        bytes32 s;
    }

    mapping(address => uint256) public accountNonce;

    /**
        @dev Use this for functions that should support meta-txs.
        @param sponsorship The sponsorship information
        @param funcSignature The function signature (selector) of the function being called
        @param encodedParams The parameters of the function, encoded using abi.encode()
     */
    modifier sponsored(
        Sponsorship memory sponsorship,
        bytes4 funcSignature,
        bytes memory encodedParams
    ) {
        _validateSponsorship(sponsorship, funcSignature, encodedParams);
        _paySponsor(
            sponsorship.sender,
            sponsorship.sponsor,
            sponsorship.sponsorFeeToken,
            sponsorship.sponsorFeeAmount
        );
        _;
    }

    /**
        @dev Validates the signature of a meta-tx sponsorship, reverts if the signature is invalid.
        @param sponsorship The sponsorship information
        @param funcSignature The function signature (selector) of the function being called
        @param encodedParams The parameters of the function, encoded using abi.encode()
     */
    function _validateSponsorship(
        Sponsorship memory sponsorship,
        bytes4 funcSignature,
        bytes memory encodedParams
    ) internal virtual {
        require(
            sponsorship.nonce == accountNonce[sponsorship.sender],
            "Sponsorable: BAD_NONCE"
        );
        require(
            block.timestamp <= sponsorship.deadline,
            "Sponsorable: SIG_DEAD"
        );

        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        bytes32 digest =
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    keccak256(
                        abi.encodePacked(
                            abi.encode(
                                chainId,
                                address(this),
                                sponsorship.sponsor,
                                sponsorship.sponsorFeeToken,
                                sponsorship.sponsorFeeAmount,
                                sponsorship.nonce,
                                sponsorship.deadline,
                                funcSignature
                            ),
                            encodedParams
                        )
                    )
                )
            );

        address recoveredAddress =
            ECDSA.recover(
                digest,
                uint8(sponsorship.v),
                sponsorship.r,
                sponsorship.s
            );
        require(
            recoveredAddress != address(0) &&
                recoveredAddress == sponsorship.sender,
            "Sponsorable: BAD_SIG"
        );

        // update nonce
        accountNonce[sponsorship.sender] = sponsorship.nonce + 1;
    }

    /**
        @dev Transfers `sponsorFeeAmount` of ERC20 token `sponsorFeeToken` from `sender` to `sponsor`.
        @param sender The user who made the meta-tx
        @param sponsor The account that should receive the sponsor fee
        @param sponsorFeeToken The ERC20 token address the sponsor fee is paid in
        @param sponsorFeeAmount The amount of sponsor fee to transfer from `sender` to `sponsor`
     */
    function _paySponsor(
        address sender,
        address sponsor,
        address sponsorFeeToken,
        uint256 sponsorFeeAmount
    ) internal virtual {
        if (sponsorFeeAmount == 0) {
            return;
        }

        IERC20 token = IERC20(sponsorFeeToken);

        // transfer tokens from sender
        token.safeTransferFrom(sender, address(this), sponsorFeeAmount);

        // transfer tokens to sponsor
        token.safeTransfer(sponsor, sponsorFeeAmount);
    }

    uint256[49] private __gap;
}
