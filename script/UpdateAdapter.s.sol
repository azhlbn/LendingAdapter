// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/Sio2Adapter.sol";

contract UpdateAdapter is Script {
    Sio2Adapter adapterNewImpl;
    ProxyAdmin admin;
    TransparentUpgradeableProxy proxy;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // admin = ProxyAdmin(0x4700c6795f8Acb98F397C13812D508780428C476);
        // proxy = TransparentUpgradeableProxy(payable(0xAB06472A169e9eA3147A722464631D10553E384D));
        admin = ProxyAdmin(0xb8C8E0438ee2c1f81E67DaD7a3002f2D6Bc24772);
        proxy = TransparentUpgradeableProxy(payable(0x7dE84319633850Bdabc557A1C61DA9E926cB4fF0));

        // new implementation
        adapterNewImpl = new Sio2Adapter();
        admin.upgrade(proxy, address(adapterNewImpl));

        console.log("New implementation:", address(adapterNewImpl));

        vm.stopBroadcast();
    }
}

//forge script UpdateAdapter --rpc-url astar --broadcast
