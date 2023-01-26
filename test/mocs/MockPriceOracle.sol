pragma solidity 0.8.4;
//SPDX-License-Identifier: MIT

contract MockPriceOracle {
    mapping(address => uint256) public prices;

    constructor(
        address nastr,
        address busdAddr
    ) {
        setInitPrices(nastr, busdAddr);
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        return prices[asset];
    }

    function setAssetPrice(address assetAddr, uint256 price) public {
        prices[assetAddr] = price;
    }

    function setInitPrices(address nastr, address busdAddr) public {
        prices[nastr] = 5340158;
        prices[busdAddr] = 99992110;
    }
}