// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {SafeERC20} from "../../libs/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OneSplitAudit} from "./imports/OneSplitAudit.sol";
import {xMPH} from "../xMPH.sol";
import {AdminControlled} from "../../libs/AdminControlled.sol";

contract OneSplitDumper is AdminControlled {
    using SafeERC20 for IERC20;

    OneSplitAudit public oneSplit;
    xMPH public xMPHToken;
    IERC20 public rewardToken;

    constructor(address _oneSplit, address _xMPHToken) {
        oneSplit = OneSplitAudit(_oneSplit);
        xMPHToken = xMPH(_xMPHToken);
        rewardToken = IERC20(address(xMPHToken.mph()));
    }

    function getDumpParams(address tokenAddress, uint256 parts)
        external
        view
        returns (uint256 returnAmount, uint256[] memory distribution)
    {
        IERC20 token = IERC20(tokenAddress);
        uint256 tokenBalance = token.balanceOf(address(this));
        (returnAmount, distribution) = oneSplit.getExpectedReturn(
            tokenAddress,
            address(rewardToken),
            tokenBalance,
            parts,
            0
        );
    }

    function dump(
        address tokenAddress,
        uint256 returnAmount,
        uint256[] calldata distribution
    ) external onlyAdmin {
        // dump token for rewardToken
        IERC20 token = IERC20(tokenAddress);
        uint256 tokenBalance = token.balanceOf(address(this));
        token.safeApprove(address(oneSplit), tokenBalance);

        uint256 rewardTokenBalanceBefore = rewardToken.balanceOf(address(this));
        oneSplit.swap(
            tokenAddress,
            address(rewardToken),
            tokenBalance,
            returnAmount,
            distribution,
            0
        );
        uint256 rewardTokenBalanceAfter = rewardToken.balanceOf(address(this));
        require(
            rewardTokenBalanceAfter > rewardTokenBalanceBefore,
            "OneSplitDumper: receivedRewardTokenAmount == 0"
        );
    }

    function notify() external onlyAdmin {
        uint256 balance = rewardToken.balanceOf(address(this));
        rewardToken.safeApprove(address(xMPHToken), balance);
        xMPHToken.distributeReward(balance);
    }
}
