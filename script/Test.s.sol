// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

interface IL {
    function getStakers() external view returns (address[] memory);
}

interface IT {
    function balanceOf(address) external view returns (uint256);
}

contract TestScript is Script {
    IL liquid = IL(0x70d264472327B67898c919809A9dc4759B6c0f27);
    IT token = IT(0xE511ED88575C57767BAfb72BfD10775413E3F2b0);

    function run() public {
        uint256 signerPk = vm.envUint("PRIVATE_KEY");
        address signer = vm.addr(signerPk);
        
        vm.startBroadcast(signerPk);

        address[] memory stakers = liquid.getStakers();

        uint256 maxBalance;
        address magnate;
        uint256 counter;

        console.log(counter);

        for (uint256 i; i < stakers.length; i++) {
            uint256 bal = token.balanceOf(stakers[i]);
            if (bal > maxBalance) {
                magnate = stakers[i];
                maxBalance = bal;
            }

            console.log(counter);
        }

        console.log("Magnate is:", magnate);
        console.log("His balance if:", maxBalance);

        vm.stopBroadcast;
    }
}
