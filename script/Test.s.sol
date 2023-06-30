// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../src/Sio2AdapterData.sol";
import "../src/Sio2Adapter.sol";
import "../src/Sio2AdapterAssetManager.sol";

contract TestScript is Script {
    Sio2Adapter adapter = Sio2Adapter(payable(0x7dE84319633850Bdabc557A1C61DA9E926cB4fF0));
    Sio2AdapterAssetManager manager = Sio2AdapterAssetManager(0x22925FE31c594aA8b1C079Ec54328cb6d87AF206);
    Sio2AdapterData data = Sio2AdapterData(0xd940B0ead69063581BD0c679650d55b56fc9E043);

    address user = 0x7ECD92b9835E0096880bF6bA778d9eA40d1338B5;
    address user2 = 0x33abf6ec717d32E12585BC88CD5746E368B24c72;
    address igor = 0x4C6B3fcAe045fCA652528e20E7A28F8d88eA353d;

    address wastr = 0xAeaaf0e2c81Af264101B9129C00F4440cCF0F720;

    uint256 private constant REWARDS_PRECISION = 1e12; // A big number to perform mul and div operations

    function run() public {
        uint256 signerPk = vm.envUint("PRIVATE_KEY");
        address signer = vm.addr(signerPk);
        
        vm.startBroadcast(signerPk);

        string memory _assetName = "ASTR";
        address _userAddr = user;

        Sio2AdapterAssetManager.Asset memory asset = manager.getAssetInfo(_assetName);
        uint256 accBTokens = asset.accBTokensPerShare;
        uint256 bIncomeDebt = adapter.userBTokensIncomeDebt(_userAddr, _assetName);
        uint256 debt = adapter.debts(_userAddr, _assetName);

        uint256 income;

        console.log("Asset address is:", asset.addr);
        uint256 currentBBalance = ERC20Upgradeable(asset.bTokenAddress).balanceOf(address(adapter));
        console.log("Current balance is:", currentBBalance);
        // if (currentBBalance > asset.lastBTokenBalance) {
        //     income = currentBBalance - asset.lastBTokenBalance;
        // }

        // uint256 estAccBTokens = accBTokens + income * REWARDS_PRECISION / currentBBalance;
        // uint256 estDebt = debt * estAccBTokens / REWARDS_PRECISION - bIncomeDebt;

        vm.stopBroadcast();
    }   
}

// == Logs ==
//   adapter proxy address: 0x94264d89C05e3B0Ec0aE8cfB1d5461bB410c07Bb
//   assetManager proxy address: 0x902A267bc7aF1A969156c05530176077620045b5
//   Data proxy address: 0x251A9Fc2a4d5ffC808CD13365e4eAF6e0bbC7ce0