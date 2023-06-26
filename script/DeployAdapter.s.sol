// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/Sio2AdapterAssetManager.sol";
import "../src/Sio2Adapter.sol";
import "../src/Sio2AdapterData.sol";
import "../src/interfaces/ISio2LendingPool.sol";

contract DeployAdapter is Script {
    Sio2AdapterAssetManager managerImpl;
    TransparentUpgradeableProxy managerProxy;
    Sio2AdapterAssetManager managerWrappedProxy;

    Sio2Adapter adapterImpl;
    TransparentUpgradeableProxy adapterProxy;
    Sio2Adapter adapterWrappedProxy;

    Sio2AdapterData dataImpl;
    TransparentUpgradeableProxy dataProxy;
    Sio2AdapterData dataWrappedProxy;

    ProxyAdmin admin;

    address public snASTR = 0x87583e06bcC3dC64c639C0f631c9bb829FB800f0;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        admin = new ProxyAdmin();

        managerImpl = new Sio2AdapterAssetManager();
        adapterImpl = new Sio2Adapter();
        dataImpl = new Sio2AdapterData();
        
        // deploy proxy contract and point it to implementation
        managerProxy = new TransparentUpgradeableProxy(address(managerImpl), address(admin), "");
        adapterProxy = new TransparentUpgradeableProxy(address(adapterImpl), address(admin), "");
        dataProxy = new TransparentUpgradeableProxy(address(dataImpl), address(admin), "");
        
        managerWrappedProxy = Sio2AdapterAssetManager(address(managerProxy));
        managerWrappedProxy.initialize(
            ISio2LendingPool(0x4df48B292C026f0340B60C582f58aa41E09fF0de),
            snASTR
        );

        adapterWrappedProxy = Sio2Adapter(payable(address(adapterProxy)));
        adapterWrappedProxy.initialize(
            ISio2LendingPool(0x4df48B292C026f0340B60C582f58aa41E09fF0de),
            IERC20Upgradeable(0xE511ED88575C57767BAfb72BfD10775413E3F2b0), //nASTR addr, but now its DAI for testing
            IERC20Upgradeable(snASTR), //snASTR, but now sDAI for testing
            ISio2IncentivesController(0xc41e6Da7F6E803514583f3b22b4Ff660CCD39B03),
            IERC20Upgradeable(0xcCA488aEEf7A1D5C633f877453784F025e7cF160), //reward token sio2
            managerWrappedProxy,
            ISio2PriceOracle(0x5f7c3639A854a27DFf64B320De5C9CAF9C4Bd323)
        );
        
        dataWrappedProxy = Sio2AdapterData(address(dataProxy));
        dataWrappedProxy.initialize(
            adapterWrappedProxy,
            managerWrappedProxy,
            ISio2LendingPool(0x4df48B292C026f0340B60C582f58aa41E09fF0de)
        );

        // in assetManager setAdapter
        managerWrappedProxy.setAdapter(Sio2Adapter(payable(address(adapterProxy))));

        // add assets in assetManager
        managerWrappedProxy.addAsset(
            "ASTR",
            0xAeaaf0e2c81Af264101B9129C00F4440cCF0F720, //Token
            0x36100c348c201A7D8242E4CC7BC3Df1e8560f0C1, //vdToken
            8 //rewardsWeight
        );

        // add some nastr to supply
        IERC20Upgradeable nastrToken = IERC20Upgradeable(0xE511ED88575C57767BAfb72BfD10775413E3F2b0);
        nastrToken.approve(
            address(adapterProxy),
            1e36
        );

        console.log("adapter proxy address:", address(adapterProxy));
        console.log("assetManager proxy address:", address(managerProxy));
        console.log("Data proxy address:", address(dataProxy));

        vm.stopBroadcast();
    }
}

// == Logs ==
//   adapter proxy address: 0x94264d89C05e3B0Ec0aE8cfB1d5461bB410c07Bb
//   assetManager proxy address: 0x902A267bc7aF1A969156c05530176077620045b5
//   Data proxy address: 0x251A9Fc2a4d5ffC808CD13365e4eAF6e0bbC7ce0