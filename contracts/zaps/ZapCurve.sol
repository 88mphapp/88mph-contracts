pragma solidity 0.5.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./imports/CurveZapIn.sol";
import "../DInterest.sol";
import "../NFT.sol";

contract ZapCurve {
    using SafeERC20 for ERC20;

    CurveZapIn public constant zapper =
        CurveZapIn(0xf9A724c2607E5766a7Bbe530D6a7e173532F9f3a);

    function zapCurveDeposit(
        address pool,
        address swapAddress,
        address inputToken,
        uint256 inputTokenAmount,
        uint256 minOutputTokenAmount,
        uint256 maturationTimestamp
    ) external {
        DInterest poolContract = DInterest(pool);
        ERC20 stablecoin = poolContract.stablecoin();
        NFT depositNFT = poolContract.depositNFT();

        // zap into curve
        uint256 outputTokenAmount = _zapTokenInCurve(
            swapAddress,
            inputToken,
            inputTokenAmount,
            minOutputTokenAmount
        );

        // create deposit
        stablecoin.safeIncreaseAllowance(pool, outputTokenAmount);
        poolContract.deposit(outputTokenAmount, maturationTimestamp);

        // transfer deposit NFT to msg.sender
        uint256 nftID = poolContract.depositsLength();
        depositNFT.safeTransferFrom(address(this), msg.sender, nftID);
    }

    function zapCurveFundAll(
        address pool,
        address swapAddress,
        address inputToken,
        uint256 inputTokenAmount,
        uint256 minOutputTokenAmount
    ) external {
        DInterest poolContract = DInterest(pool);
        ERC20 stablecoin = poolContract.stablecoin();
        NFT fundingNFT = poolContract.fundingNFT();

        // zap into curve
        uint256 outputTokenAmount = _zapTokenInCurve(
            swapAddress,
            inputToken,
            inputTokenAmount,
            minOutputTokenAmount
        );

        // create funding
        stablecoin.safeIncreaseAllowance(pool, outputTokenAmount);
        poolContract.fundAll();

        // transfer funding NFT to msg.sender
        uint256 nftID = poolContract.fundingListLength();
        fundingNFT.safeTransferFrom(address(this), msg.sender, nftID);
    }

    function zapCurveFundMultiple(
        address pool,
        address swapAddress,
        address inputToken,
        uint256 inputTokenAmount,
        uint256 minOutputTokenAmount,
        uint256 toDepositID
    ) external {
        DInterest poolContract = DInterest(pool);
        ERC20 stablecoin = poolContract.stablecoin();
        NFT fundingNFT = poolContract.fundingNFT();

        // zap into curve
        uint256 outputTokenAmount = _zapTokenInCurve(
            swapAddress,
            inputToken,
            inputTokenAmount,
            minOutputTokenAmount
        );

        // create funding
        stablecoin.safeIncreaseAllowance(pool, outputTokenAmount);
        poolContract.fundMultiple(toDepositID);

        // transfer funding NFT to msg.sender
        uint256 nftID = poolContract.fundingListLength();
        fundingNFT.safeTransferFrom(address(this), msg.sender, nftID);
    }

    function _zapTokenInCurve(
        address swapAddress,
        address inputToken,
        uint256 inputTokenAmount,
        uint256 minOutputTokenAmount
    ) internal returns (uint256 outputTokenAmount) {
        ERC20 inputTokenContract = ERC20(inputToken);

        // transfer inputToken from msg.sender
        inputTokenContract.safeTransferFrom(
            msg.sender,
            address(this),
            inputTokenAmount
        );

        // zap inputToken into curve
        outputTokenAmount =
            zapper.ZapIn(
                address(this),
                inputToken,
                swapAddress,
                inputTokenAmount,
                minOutputTokenAmount
            );
    }
}
