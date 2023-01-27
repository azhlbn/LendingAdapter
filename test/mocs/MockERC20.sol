pragma solidity 0.8.4;
//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract MockERC20 is ERC20Burnable {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {

    }

    function mint(address user, uint256 amount) public {
        _mint(user, amount);
    }

    function burn(address user, uint256 amount) public {
        _burn(user, amount);
    }
}