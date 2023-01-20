pragma solidity 0.8.4;
//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/ERC20Upgradeable.sol";

contract MockSCollateralToken is ERC20Upgradeable {
    function initialize(string memory name, string memory symbol) public initializer {
        __ERC20_init(name, symbol);
    }

    function mint(address user, uint256 amount) public {
        _mint(user, amount);
    }
}