//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface IWASTR {
    function deposit() external payable;

    function withdraw(uint256) external;
}
