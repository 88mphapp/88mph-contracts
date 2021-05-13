// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./imports/CurveZapIn.sol";
import "../DInterest.sol";
import "../tokens/NFT.sol";
import "../tokens/FundingMultitoken.sol";

contract ZapCurve is ERC1155Receiver, IERC721Receiver {
    using SafeERC20Upgradeable for ERC20Upgradeable;

    modifier active {
        isActive = true;
        _;
        isActive = false;
    }

    CurveZapIn public constant zapper =
        CurveZapIn(0xf9A724c2607E5766a7Bbe530D6a7e173532F9f3a);
    bytes internal constant NULL_BYTES = bytes("");
    bool public isActive;

    function zapCurveDeposit(
        address pool,
        address swapAddress,
        address inputToken,
        uint256 inputTokenAmount,
        uint256 minOutputTokenAmount,
        uint64 maturationTimestamp
    ) external active {
        DInterest poolContract = DInterest(pool);
        ERC20Upgradeable stablecoin = poolContract.stablecoin();
        NFT depositNFT = poolContract.depositNFT();

        // zap into curve
        uint256 outputTokenAmount =
            _zapTokenInCurve(
                swapAddress,
                inputToken,
                inputTokenAmount,
                minOutputTokenAmount
            );

        // create deposit
        stablecoin.safeIncreaseAllowance(pool, outputTokenAmount);
        (uint64 depositID, ) =
            poolContract.deposit(outputTokenAmount, maturationTimestamp);

        // transfer deposit multitokens to msg.sender
        depositNFT.safeTransferFrom(address(this), msg.sender, depositID);
    }

    function zapCurveFund(
        address pool,
        address swapAddress,
        address inputToken,
        uint256 inputTokenAmount,
        uint256 minOutputTokenAmount,
        uint64 depositID
    ) external active {
        DInterest poolContract = DInterest(pool);
        ERC20Upgradeable stablecoin = poolContract.stablecoin();
        FundingMultitoken fundingMultitoken = poolContract.fundingMultitoken();

        // zap into curve
        uint256 outputTokenAmount =
            _zapTokenInCurve(
                swapAddress,
                inputToken,
                inputTokenAmount,
                minOutputTokenAmount
            );

        // create funding
        stablecoin.safeIncreaseAllowance(pool, outputTokenAmount);
        uint64 fundingID = poolContract.fund(depositID, outputTokenAmount);

        // transfer funding multitoken to msg.sender
        fundingMultitoken.safeTransferFrom(
            address(this),
            msg.sender,
            fundingID,
            fundingMultitoken.balanceOf(address(this), fundingID),
            NULL_BYTES
        );
        // transfer remaining stablecoins to msg.sender
        stablecoin.safeTransfer(
            msg.sender,
            stablecoin.balanceOf(address(this))
        );
    }

    function onERC1155Received(
        address, /*operator*/
        address, /*from*/
        uint256, /*id*/
        uint256, /*value*/
        bytes calldata /*data*/
    ) external view override returns (bytes4) {
        require(isActive, "ZapCurve: inactive");
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address, /*operator*/
        address, /*from*/
        uint256[] calldata, /*ids*/
        uint256[] calldata, /*values*/
        bytes calldata /*data*/
    ) external view override returns (bytes4) {
        require(isActive, "ZapCurve: inactive");
        return this.onERC1155BatchReceived.selector;
    }

    function onERC721Received(
        address, /*operator*/
        address, /*from*/
        uint256, /*tokenId*/
        bytes memory /*data*/
    ) external view override returns (bytes4) {
        require(isActive, "ZapCurve: inactive");
        return this.onERC721Received.selector;
    }

    function _zapTokenInCurve(
        address swapAddress,
        address inputToken,
        uint256 inputTokenAmount,
        uint256 minOutputTokenAmount
    ) internal returns (uint256 outputTokenAmount) {
        ERC20Upgradeable inputTokenContract = ERC20Upgradeable(inputToken);

        // transfer inputToken from msg.sender
        inputTokenContract.safeTransferFrom(
            msg.sender,
            address(this),
            inputTokenAmount
        );

        // zap inputToken into curve
        inputTokenContract.safeIncreaseAllowance(
            address(zapper),
            inputTokenAmount
        );
        outputTokenAmount = zapper.ZapIn(
            address(this),
            inputToken,
            swapAddress,
            inputTokenAmount,
            minOutputTokenAmount
        );
    }
}
