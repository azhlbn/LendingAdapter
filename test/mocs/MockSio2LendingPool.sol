pragma solidity 0.8.4;
//SPDX-License-Identifier: MIT

import "./MockSCollateralToken.sol";
import "../../src/libraries/ReserveConfiguration.sol";

contract MockSio2LendingPool {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    uint256 public collateralAmount;
    MockSCollateralToken public snastr;
    DataTypes.ReserveConfigurationMap public busdConfigMap;

    constructor(MockSCollateralToken _snastr) {
        snastr = _snastr;
        busdConfigMap.data = 27671057969860373126976;
    }

    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external {
        collateralAmount += amount;
        snastr.mint(msg.sender, amount);
    }

    // returns configuration map for busd
    function getConfiguration(
        address asset
    ) external view returns (DataTypes.ReserveConfigurationMap memory) {
        return busdConfigMap;
    }
}
