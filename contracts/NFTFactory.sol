pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import "./libs/CloneFactory.sol";
import "./NFT.sol";

contract NFTFactory is CloneFactory {
    address public template;

    event CreateClone(address _clone);

    constructor(address _template) public {
        template = _template;
    }

    function createClone(
        string calldata _tokenName,
        string calldata _tokenSymbol
    ) external returns (NFT) {
        NFT clone = NFT(createClone(template));

        // initialize
        clone.init(
            msg.sender,
            _tokenName,
            _tokenSymbol
        );

        emit CreateClone(address(clone));
        return clone;
    }

    function isClone(address query) external view returns (bool) {
        return isClone(template, query);
    }
}
