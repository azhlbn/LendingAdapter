//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface ISio2PriceOracle { //0x5f7c3639A854a27DFf64B320De5C9CAF9C4Bd323
  /***********
    @dev returns the asset price in ETH
     */
  function getAssetPrice(address asset) external view returns (uint256);

  /***********
    @dev sets the asset price, in wei
     */
  function setAssetPrice(address asset, uint256 price) external;
}