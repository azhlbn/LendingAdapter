pragma solidity 0.8.4;
//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./interfaces/ISio2LendingPool.sol";
// import "./interfaces/ISio2PriceOracle.sol";
// import "./interfaces/ISio2IncentivesController.sol";
import "./Sio2Adapter.sol";

/* 
- add events
- add role for adapter
 */

contract Sio2AdapterAssetManager is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap; // used to extract risk parameters of an asset

    //Interfaces
    ISio2LendingPool public pool;
    Sio2Adapter public adapter;

    uint256 private constant REWARDS_PRECISION = 1e12; // A big number to perform mul and div operations

    string[] public assets;
    mapping(string => Asset) public assetInfo;
    address[] public assetsAddresses;
    address[] public bTokens;
    uint256 public totalRewardsWeight; // the sum of the weights of collateral and borrowed assets

    struct Asset {
        uint256 id;
        string name;
        address addr;
        address bTokenAddress;
        uint256 liquidationThreshold;
        uint256 lastBTokenBalance;
        uint256 totalBorrowed;
        uint256 rewardsWeight;
        uint256 accBTokensPerShare;
        uint256 accBorrowedRewardsPerShare;
    }

    event AddAsset(address owner, string indexed assetName, address indexed assetAddress);
    event RemoveAsset(address owner, string indexed assetName);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        ISio2LendingPool _pool
    ) public initializer {
        __Ownable_init();

        pool = _pool;
    }

    modifier onlyAdapter() {
        require(msg.sender == address(adapter), "Allowed only for adapter");
        _;
    }

    // @notice Allows owner to add new asset
    function addAsset(
        string memory _assetName,
        address _assetAddress,
        address _bToken,
        uint256 _rewardsWeight
    ) external onlyOwner {
        require(assetInfo[_assetName].addr == address(0), "Asset already added");
        require(_assetAddress != address(0), "Zero address alarm!");

        // get liquidationThreshold for asset from sio2
        DataTypes.ReserveConfigurationMap memory data = pool.getConfiguration(_assetAddress);
        uint256 lt = data.getLiquidationThreshold();

        Asset memory asset = Asset({
            id: assets.length,
            name: _assetName,
            addr: _assetAddress,
            bTokenAddress: _bToken,
            liquidationThreshold: lt,
            lastBTokenBalance: IERC20Upgradeable(_bToken).balanceOf(address(this)),
            accBTokensPerShare: 0,
            totalBorrowed: 0,
            rewardsWeight: _rewardsWeight,
            accBorrowedRewardsPerShare: 0
        });

        assets.push(asset.name);
        assetsAddresses.push(asset.addr);
        assetInfo[_assetName] = asset;
        bTokens.push(_bToken);
        totalRewardsWeight += _rewardsWeight;

        emit AddAsset(msg.sender, _assetName, _assetAddress);
    }

    // @notice Removes an asset
    function removeAsset(string memory _assetName) external onlyOwner {
        require(
            assetInfo[_assetName].addr != address(0),
            "There is no such asset"
        );

        Asset memory asset = assetInfo[_assetName];

        // remove from assets
        string memory lastAsset = assets[assets.length - 1];
        assets[asset.id] = lastAsset;
        assets.pop();

        // remove from assetsAddresses
        address lastAddr = assetsAddresses[assetsAddresses.length - 1];
        assetsAddresses[asset.id] = lastAddr;
        assetsAddresses.pop();

        // remove addr from bTokens
        address lastBAddr = bTokens[bTokens.length - 1];
        bTokens[asset.id] = lastBAddr;
        bTokens.pop();

        // update totalRewardsWeight
        totalRewardsWeight -= asset.rewardsWeight;

        // update id of last asset and remove deleted struct
        assetInfo[lastAsset].id = asset.id;
        delete assetInfo[_assetName];

        emit RemoveAsset(msg.sender, _assetName);
    }

    function addBTokens(address _bToken) public {
        bTokens.push(_bToken);
    }

    function increaseAssetsTotalBorrowed(string memory _assetName, uint256 _amount) external onlyAdapter {
        assetInfo[_assetName].totalBorrowed += _amount;
    }

    function decreaseAssetsTotalBorrowed(string memory _assetName, uint256 _amount) external onlyAdapter {
        assetInfo[_assetName].totalBorrowed -= _amount;
    }

    function increaseAccBorrowedRewardsPerShare(string memory _assetName, uint256 _assetRewards) external onlyAdapter {
        Asset storage asset = assetInfo[_assetName];
        asset.accBorrowedRewardsPerShare += _assetRewards * REWARDS_PRECISION / asset.totalBorrowed;
    }

    function increaseAccBTokensPerShare(string memory _assetName, uint256 _income) external onlyAdapter {
        Asset storage asset = assetInfo[_assetName];
        asset.accBTokensPerShare += _income * REWARDS_PRECISION / asset.totalBorrowed;
    }

    function updateLastBTokenBalance(string memory _assetName) external onlyAdapter {
        Asset storage asset = assetInfo[_assetName];
        asset.lastBTokenBalance = IERC20Upgradeable(asset.bTokenAddress).balanceOf(address(this));
    }

    function getBTokens() public view returns (address[] memory) {
        return bTokens;
    }

    function getAssetsNames() public view returns (string[] memory) {
        return assets;
    }

    function setAdapter(Sio2Adapter _adapter) public onlyOwner {
        adapter = _adapter;
    }
}