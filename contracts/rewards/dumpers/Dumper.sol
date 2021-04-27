// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "./OneSplitDumper.sol";
import "./withdrawers/CurveLPWithdrawer.sol";
import "./withdrawers/YearnWithdrawer.sol";

contract Dumper is OneSplitDumper, CurveLPWithdrawer, YearnWithdrawer {
    constructor(address _oneSplit, address _xMPHToken)
        OneSplitDumper(_oneSplit, _xMPHToken)
    {}
}
