// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "../src/Some.sol";

contract Deploy is Script {
    Some public some;

    function run() public {
        some = new Some();
    }
}