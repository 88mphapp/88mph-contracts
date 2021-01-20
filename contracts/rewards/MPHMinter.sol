pragma solidity 0.5.17;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./MPHToken.sol";
import "../models/issuance/IMPHIssuanceModel.sol";
import "./Vesting.sol";

contract MPHMinter is Ownable {
    using Address for address;
    using SafeMath for uint256;

    mapping(address => bool) public poolWhitelist;

    modifier onlyWhitelistedPool {
        require(poolWhitelist[msg.sender], "MPHMinter: sender not whitelisted");
        _;
    }

    event ESetParamAddress(
        address indexed sender,
        string indexed paramName,
        address newValue
    );
    event WhitelistPool(
        address indexed sender,
        address pool,
        bool isWhitelisted
    );
    event MintDepositorReward(
        address indexed sender,
        address indexed to,
        uint256 depositorReward
    );
    event TakeBackDepositorReward(
        address indexed sender,
        address indexed from,
        uint256 takeBackAmount
    );
    event MintFunderReward(
        address indexed sender,
        address indexed to,
        uint256 funderReward
    );

    /**
        External contracts
     */
    MPHToken public mph;
    address public govTreasury;
    address public devWallet;
    IMPHIssuanceModel public issuanceModel;
    Vesting public vesting;

    constructor(
        address _mph,
        address _govTreasury,
        address _devWallet,
        address _issuanceModel,
        address _vesting
    ) public {
        mph = MPHToken(_mph);
        govTreasury = _govTreasury;
        devWallet = _devWallet;
        issuanceModel = IMPHIssuanceModel(_issuanceModel);
        vesting = Vesting(_vesting);
    }

    /**
        @notice Mints the MPH reward to a depositor upon deposit.
        @param  to The depositor
        @param  depositAmount The deposit amount in the pool's stablecoins
        @param  depositPeriodInSeconds The deposit's lock period in seconds
        @param  interestAmount The deposit's fixed-rate interest amount in the pool's stablecoins
        @return depositorReward The MPH amount to mint to the depositor
     */
    function mintDepositorReward(
        address to,
        uint256 depositAmount,
        uint256 depositPeriodInSeconds,
        uint256 interestAmount
    ) external onlyWhitelistedPool returns (uint256) {
        if (mph.owner() != address(this)) {
            // not the owner of the MPH token, cannot mint
            emit MintDepositorReward(msg.sender, to, 0);
            return 0;
        }
    
        (
            uint256 depositorReward,
            uint256 devReward,
            uint256 govReward
        ) = issuanceModel.computeDepositorReward(
            msg.sender,
            depositAmount,
            depositPeriodInSeconds,
            interestAmount
        );
        if (depositorReward == 0 && devReward == 0 && govReward == 0) {
            return 0;
        }

        // mint and vest depositor reward
        mph.ownerMint(address(this), depositorReward);
        uint256 vestPeriodInSeconds = issuanceModel
            .poolDepositorRewardVestPeriod(msg.sender);
        if (vestPeriodInSeconds == 0) {
            // no vesting, transfer to `to`
            mph.transfer(to, depositorReward);
        } else {
            // vest the MPH to `to`
            mph.increaseAllowance(address(vesting), depositorReward);
            vesting.vest(to, depositorReward, vestPeriodInSeconds);
        }

        mph.ownerMint(devWallet, devReward);
        mph.ownerMint(govTreasury, govReward);

        emit MintDepositorReward(msg.sender, to, depositorReward);

        return depositorReward;
    }

    /**
        @notice Takes back MPH from depositor upon withdrawal.
                If takeBackAmount > devReward + govReward, the extra MPH should be burnt.
        @param  from The depositor
        @param  mintMPHAmount The MPH amount originally minted to the depositor as reward
        @param  early True if the deposit is withdrawn early, false if the deposit is mature
        @return takeBackAmount The MPH amount to take back from the depositor
     */
    function takeBackDepositorReward(
        address from,
        uint256 mintMPHAmount,
        bool early
    ) external onlyWhitelistedPool returns (uint256) {
        (
            uint256 takeBackAmount,
            uint256 devReward,
            uint256 govReward
        ) = issuanceModel.computeTakeBackDepositorRewardAmount(
            msg.sender,
            mintMPHAmount,
            early
        );
        if (takeBackAmount == 0 && devReward == 0 && govReward == 0) {
            return 0;
        }
        require(
            takeBackAmount >= devReward.add(govReward),
            "MPHMinter: takeBackAmount < devReward + govReward"
        );
        mph.transferFrom(from, address(this), takeBackAmount);
        mph.transfer(devWallet, devReward);
        mph.transfer(govTreasury, govReward);
        mph.burn(takeBackAmount.sub(devReward).sub(govReward));

        emit TakeBackDepositorReward(msg.sender, from, takeBackAmount);

        return takeBackAmount;
    }

    /**
        @notice Mints the MPH reward to a deficit funder upon withdrawal of an underlying deposit.
        @param  to The funder
        @param  depositAmount The deposit amount in the pool's stablecoins
        @param  fundingCreationTimestamp The timestamp of the funding's creation, in seconds
        @param  maturationTimestamp The maturation timestamp of the deposit, in seconds
        @param  interestPayoutAmount The interest payout amount to the funder, in the pool's stablecoins.
                                     Includes the interest from other funded deposits.
        @param  early True if the deposit is withdrawn early, false if the deposit is mature
        @return funderReward The MPH amount to mint to the funder
     */
    function mintFunderReward(
        address to,
        uint256 depositAmount,
        uint256 fundingCreationTimestamp,
        uint256 maturationTimestamp,
        uint256 interestPayoutAmount,
        bool early
    ) external onlyWhitelistedPool returns (uint256) {
        if (mph.owner() != address(this)) {
            // not the owner of the MPH token, cannot mint
            emit MintDepositorReward(msg.sender, to, 0);
            return 0;
        }

        (
            uint256 funderReward,
            uint256 devReward,
            uint256 govReward
        ) = issuanceModel.computeFunderReward(
            msg.sender,
            depositAmount,
            fundingCreationTimestamp,
            maturationTimestamp,
            interestPayoutAmount,
            early
        );
        if (funderReward == 0 && devReward == 0 && govReward == 0) {
            return 0;
        }

        // mint and vest funder reward
        mph.ownerMint(address(this), funderReward);
        uint256 vestPeriodInSeconds = issuanceModel.poolFunderRewardVestPeriod(
            msg.sender
        );
        if (vestPeriodInSeconds == 0) {
            // no vesting, transfer to `to`
            mph.transfer(to, funderReward);
        } else {
            // vest the MPH to `to`
            mph.increaseAllowance(address(vesting), funderReward);
            vesting.vest(to, funderReward, vestPeriodInSeconds);
        }
        mph.ownerMint(devWallet, devReward);
        mph.ownerMint(govTreasury, govReward);

        emit MintFunderReward(msg.sender, to, funderReward);

        return funderReward;
    }

    /**
        Param setters
     */
    function setGovTreasury(address newValue) external onlyOwner {
        require(newValue != address(0), "MPHMinter: 0 address");
        govTreasury = newValue;
        emit ESetParamAddress(msg.sender, "govTreasury", newValue);
    }

    function setDevWallet(address newValue) external onlyOwner {
        require(newValue != address(0), "MPHMinter: 0 address");
        devWallet = newValue;
        emit ESetParamAddress(msg.sender, "devWallet", newValue);
    }

    function setMPHTokenOwner(address newValue) external onlyOwner {
        require(newValue != address(0), "MPHMinter: 0 address");
        mph.transferOwnership(newValue);
        emit ESetParamAddress(msg.sender, "mphTokenOwner", newValue);
    }

    function setMPHTokenOwnerToZero() external onlyOwner {
        mph.renounceOwnership();
        emit ESetParamAddress(msg.sender, "mphTokenOwner", address(0));
    }

    function setIssuanceModel(address newValue) external onlyOwner {
        require(newValue.isContract(), "MPHMinter: not contract");
        issuanceModel = IMPHIssuanceModel(newValue);
        emit ESetParamAddress(msg.sender, "issuanceModel", newValue);
    }

    function setVesting(address newValue) external onlyOwner {
        require(newValue.isContract(), "MPHMinter: not contract");
        vesting = Vesting(newValue);
        emit ESetParamAddress(msg.sender, "vesting", newValue);
    }

    function setPoolWhitelist(address pool, bool isWhitelisted)
        external
        onlyOwner
    {
        require(pool.isContract(), "MPHMinter: pool not contract");
        poolWhitelist[pool] = isWhitelisted;
        emit WhitelistPool(msg.sender, pool, isWhitelisted);
    }
}
