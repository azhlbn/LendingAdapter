//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./MockSCollateralToken.sol";
import "./MockVDToken.sol";
import "./MockERC20.sol";

contract MockIncentivesController {
    MockSCollateralToken public snastr;
    MockVDToken public vdbusd;
    MockERC20 public rewardToken;

    constructor(
        MockSCollateralToken _snastr,
        MockVDToken _vdbusd,
        MockERC20 _rewardToken
    ) {
        snastr = _snastr;
        vdbusd = _vdbusd;
        rewardToken = _rewardToken;
    }

    function claimRewards(
        address[] calldata assets,
        uint256 amount,
        address to
    ) external returns (uint256) {
        require(amount == getUserUnclaimedRewards(msg.sender), "MockIncentive: Not enough rewards");
        snastr.setLastClaimedRewardTime();
        vdbusd.setLastClaimedRewardTime();
        rewardToken.mint(msg.sender, amount);
    }

    function getUserUnclaimedRewards(
        address user
    ) public view returns (uint256) {
        uint256 lastTimeDebt = vdbusd.lastClaimedRewardTime();
        uint256 lastTimeColl = snastr.lastClaimedRewardTime();
        uint256 incomeDebtRewards;
        uint256 incomeCollRewards;
        lastTimeDebt > 0 ? 
        incomeDebtRewards = lastTimeDebt - block.timestamp : 0;
        lastTimeColl > 0 ?
        incomeCollRewards = lastTimeColl - block.timestamp : 0;
        return incomeDebtRewards + incomeCollRewards;
    }
}
