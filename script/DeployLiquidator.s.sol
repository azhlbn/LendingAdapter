// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "../src/Liquidator.sol";

contract DeployLiquidator is Script {
    Liquidator liquidator;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        liquidator = new Liquidator(
            ISio2LendingPool(0x4df48B292C026f0340B60C582f58aa41E09fF0de),
            Sio2Adapter(payable(0x4C1fb756da55E4c5Cc9A3D90aD94E34DFE7B84d9)),
            Sio2AdapterAssetManager(0x5c7d876d074B13f32f683c92d4fC58FD49b90e71),
            ISio2LendingPoolAddressesProvider(0x2660e0668dd5A18Ed092D5351FfF7B0A403f9721),
            Sio2AdapterData(0x2f17EC75D21541e378d006c6f5f5B1b5F2c111bf),
            0xE511ED88575C57767BAfb72BfD10775413E3F2b0
        );

        vm.stopBroadcast();

        console.log("liquidator address:", address(liquidator));
    }
}

// deployed liq 0x54597cAFB365c6C09d52bB7750092bD2135259f6