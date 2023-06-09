// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../src/Sio2AdapterData.sol";

contract TestScript is Script {
    Sio2AdapterData data = Sio2AdapterData(0x01Daa46901103aED46F86d8be5376c3e12E8bd8b);
    address user = 0x7ECD92b9835E0096880bF6bA778d9eA40d1338B5;

    function run() public {
        uint256 signerPk = vm.envUint("PRIVATE_KEY");
        address signer = vm.addr(signerPk);

        uint256[] memory before = new uint256[](3);
        uint256[] memory later = new uint256[](3);
        
        vm.startBroadcast(signerPk);
    
        (before, later) = data.borrowRepayShift(
            user,
            1e16,
            "BUSD",
            true
        );

        console.log("before:");
        console.log("borrow available:", before[0]);
        console.log("borrow limit used:", before[1]);
        console.log("hf:", before[2]);
        console.log("later:");
        console.log("borrow available:", later[0]);
        console.log("borrow limit used:", later[1]);
        console.log("hf:", later[2]);
        console.log("balance is:", signer.balance);

        vm.stopBroadcast();
    }   
}