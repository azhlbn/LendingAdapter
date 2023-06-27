// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../src/Sio2AdapterData.sol";
import "../src/Sio2Adapter.sol";
import "../src/Sio2AdapterAssetManager.sol";

contract TestScript is Script {
    Sio2AdapterData data = Sio2AdapterData(0x01Daa46901103aED46F86d8be5376c3e12E8bd8b);
    Sio2Adapter adapter = Sio2Adapter(payable(0x94264d89C05e3B0Ec0aE8cfB1d5461bB410c07Bb));
    Sio2AdapterAssetManager manager = Sio2AdapterAssetManager(0x22925FE31c594aA8b1C079Ec54328cb6d87AF206);
    address user = 0x7ECD92b9835E0096880bF6bA778d9eA40d1338B5;
    address user2 = 0x33abf6ec717d32E12585BC88CD5746E368B24c72;

    function run() public {
        uint256 signerPk = vm.envUint("PRIVATE_KEY");
        address signer = vm.addr(signerPk);
        
        vm.startBroadcast(signerPk);

        manager.changeRewWeight();        

        vm.stopBroadcast();
    }   
}

// == Logs ==
//   adapter proxy address: 0x94264d89C05e3B0Ec0aE8cfB1d5461bB410c07Bb
//   assetManager proxy address: 0x902A267bc7aF1A969156c05530176077620045b5
//   Data proxy address: 0x251A9Fc2a4d5ffC808CD13365e4eAF6e0bbC7ce0