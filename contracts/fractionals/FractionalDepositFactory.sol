// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../libs/CloneFactory.sol";
import "./FractionalDeposit.sol";
import "../DInterest.sol";
import "../NFT.sol";
import "../rewards/MPHToken.sol";

contract FractionalDepositFactory is CloneFactory, IERC721Receiver {
    address public template;
    MPHToken public mph;

    event CreateClone(address _clone);

    constructor(address _template, address _mph) {
        template = _template;
        mph = MPHToken(_mph);
    }

    function createFractionalDeposit(
        address _pool,
        uint256 _nftID,
        string calldata _tokenName,
        string calldata _tokenSymbol
    ) external returns (FractionalDeposit) {
        FractionalDeposit clone = FractionalDeposit(createClone(template));

        // transfer NFT from msg.sender to clone
        DInterest pool = DInterest(_pool);
        NFT nft = NFT(pool.depositNFT());
        nft.safeTransferFrom(msg.sender, address(this), _nftID);
        nft.safeTransferFrom(address(this), address(clone), _nftID);

        // transfer MPH reward from msg.sender
        DInterest.Deposit memory deposit = pool.getDeposit(_nftID);
        uint256 mintMPHAmount = deposit.mintMPHAmount;
        mph.transferFrom(msg.sender, address(this), mintMPHAmount);
        mph.increaseAllowance(address(clone), mintMPHAmount);

        // initialize
        clone.init(_pool, address(mph), _nftID, _tokenName, _tokenSymbol);
        clone.transferOwnership(msg.sender);
        clone.transfer(msg.sender, clone.balanceOf(address(this)));

        emit CreateClone(address(clone));
        return clone;
    }

    function isFractionalDeposit(address query) external view returns (bool) {
        return isClone(template, query);
    }

    function onERC721Received(
        address, /*operator*/
        address, /*from*/
        uint256, /*tokenId*/
        bytes memory /*data*/
    ) public pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
