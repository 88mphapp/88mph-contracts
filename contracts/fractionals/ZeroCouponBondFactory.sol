pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../libs/CloneFactory.sol";
import "./ZeroCouponBond.sol";

contract ZeroCouponBondFactory is CloneFactory {
    address public template;
    address public fractionalDepositFactory;

    event CreateClone(address _clone);

    constructor(address _template, address _fractionalDepositFactory) public {
        template = _template;
        fractionalDepositFactory = _fractionalDepositFactory;
    }

    function createZeroCouponBond(
        address _pool,
        uint256 _maturationTimetstamp,
        string calldata _tokenName,
        string calldata _tokenSymbol
    ) external returns (ZeroCouponBond) {
        ZeroCouponBond clone = ZeroCouponBond(createClone(template));

        // initialize
        clone.init(
            _pool,
            fractionalDepositFactory,
            _maturationTimetstamp,
            _tokenName,
            _tokenSymbol
        );

        emit CreateClone(address(clone));
        return clone;
    }

    function isZeroCouponBond(address query) external view returns (bool) {
        return isClone(template, query);
    }
}
