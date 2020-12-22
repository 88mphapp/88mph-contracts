pragma solidity 0.5.17;

interface CurveZapIn {
    /**
        @notice This function adds liquidity to a Curve pool with ETH or ERC20 tokens
        @param toWhomToIssue The address to return the Curve LP tokens to
        @param fromToken The ERC20 token used for investment (address(0x00) if ether)
        @param swapAddress Curve swap address for the pool
        @param incomingTokenQty The amount of fromToken to invest
        @param minPoolTokens The minimum acceptable quantity of tokens to receive. Reverts otherwise
        @return Amount of Curve LP tokens received
    */
    function ZapIn(
        address toWhomToIssue,
        address fromToken,
        address swapAddress,
        uint256 incomingTokenQty,
        uint256 minPoolTokens
    ) external payable returns (uint256 crvTokensBought);
}
