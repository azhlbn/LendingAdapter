pragma solidity 0.8.4;
//SPDX-License-Identifier: MIT

contract MockPriceOracle {
    mapping(address => uint256) public prices;

    constructor(
        address nastr,
        address busdAddr
    ) {
        prices[nastr] = 5340158;
        prices[busdAddr] = 99992110;
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        return prices[asset];
    }
}