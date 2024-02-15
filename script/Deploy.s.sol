// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "../src/Sio2Adapter.sol";

contract Deploy is Script {
    Sio2Adapter deployedContract;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        deployedContract = new Sio2Adapter();

        console.log("Contract address:", address(deployedContract));

        vm.stopBroadcast();
    }
}