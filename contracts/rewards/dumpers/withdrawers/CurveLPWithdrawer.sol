// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICurveFi, Zap} from "../imports/Curve.sol";
import {AdminControlled} from "../../../libs/AdminControlled.sol";

contract CurveLPWithdrawer is AdminControlled {
    function curveWithdraw2(
        address lpTokenAddress,
        address curvePoolAddress,
        uint256[2] calldata minAmounts
    ) external onlyAdmin {
        IERC20 lpToken = IERC20(lpTokenAddress);
        uint256 lpTokenBalance = lpToken.balanceOf(address(this));
        ICurveFi curvePool = ICurveFi(curvePoolAddress);
        curvePool.remove_liquidity(lpTokenBalance, minAmounts);
    }

    function curveWithdraw3(
        address lpTokenAddress,
        address curvePoolAddress,
        uint256[3] calldata minAmounts
    ) external onlyAdmin {
        IERC20 lpToken = IERC20(lpTokenAddress);
        uint256 lpTokenBalance = lpToken.balanceOf(address(this));
        ICurveFi curvePool = ICurveFi(curvePoolAddress);
        curvePool.remove_liquidity(lpTokenBalance, minAmounts);
    }

    function curveWithdraw4(
        address lpTokenAddress,
        address curvePoolAddress,
        uint256[4] calldata minAmounts
    ) external onlyAdmin {
        IERC20 lpToken = IERC20(lpTokenAddress);
        uint256 lpTokenBalance = lpToken.balanceOf(address(this));
        ICurveFi curvePool = ICurveFi(curvePoolAddress);
        curvePool.remove_liquidity(lpTokenBalance, minAmounts);
    }

    function curveWithdraw5(
        address lpTokenAddress,
        address curvePoolAddress,
        uint256[5] calldata minAmounts
    ) external onlyAdmin {
        IERC20 lpToken = IERC20(lpTokenAddress);
        uint256 lpTokenBalance = lpToken.balanceOf(address(this));
        ICurveFi curvePool = ICurveFi(curvePoolAddress);
        curvePool.remove_liquidity(lpTokenBalance, minAmounts);
    }

    function curveWithdrawOneCoin(
        address lpTokenAddress,
        address curvePoolAddress,
        int128 coinIndex,
        uint256 minAmount
    ) external onlyAdmin {
        IERC20 lpToken = IERC20(lpTokenAddress);
        uint256 lpTokenBalance = lpToken.balanceOf(address(this));
        Zap curvePool = Zap(curvePoolAddress);
        curvePool.remove_liquidity_one_coin(
            lpTokenBalance,
            coinIndex,
            minAmount
        );
    }
}
