pragma solidity 0.8.4;
//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockVDToken is ERC20 {
    uint256 public lastClaimedTime;
    uint256 public lastClaimedRewardTime;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address user, uint256 amount) public {
        _mint(user, amount);
        if (lastClaimedTime == 0) {
            lastClaimedTime = block.timestamp;
            lastClaimedRewardTime = block.timestamp;
        }
    }

    function setLastClaimedRewardTime() public {
        lastClaimedRewardTime = block.timestamp;
    }
}