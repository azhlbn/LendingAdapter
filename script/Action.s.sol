// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "../src/Sio2AdapterAssetManager.sol";

contract Action is Script {
    Sio2AdapterAssetManager managerWrappedProxy = Sio2AdapterAssetManager(0xaF59698A87ACAC4b7Ca72c785BdE15D84Cdac4d8);

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        managerWrappedProxy.addAsset(
            "ASTR",
            0xAeaaf0e2c81Af264101B9129C00F4440cCF0F720, //Token
            0x36100c348c201A7D8242E4CC7BC3Df1e8560f0C1, //vdToken
            8 //rewardsWeight
        );

        vm.stopBroadcast();
    }
}