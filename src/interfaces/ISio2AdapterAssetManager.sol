//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface ISio2AdapterAssetManager {
    event AddAsset(address owner, string indexed assetName, address indexed assetAddress);
    event Initialized(uint8 version);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RemoveAsset(address owner, string indexed assetName);
    event SetAdapter(address who, address adapterAddress);
    event UpdateBalError(address user, string utilityName, uint256 amount, string reason);
    event UpdateBalSuccess(address user, string utilityName, uint256 amount);

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

    function adapter() external view returns (address);
    function adaptersDistributor() external view returns (address);
    function addAsset(string memory _assetName, address _assetAddress, address _bToken, uint256 _rewardsWeight)
        external;
    function addAsset(address _assetAddress, address _bToken, uint256 _rewardsWeight) external;
    function assetInfo(string memory)
        external
        view
        returns (
            uint256 id,
            string memory name,
            address addr,
            address bTokenAddress,
            uint256 liquidationThreshold,
            uint256 lastBTokenBalance,
            uint256 totalBorrowed,
            uint256 rewardsWeight,
            uint256 accBTokensPerShare,
            uint256 accBorrowedRewardsPerShare
        );
    function assetNameExist(string memory) external view returns (bool);
    function assets(uint256) external view returns (string memory);
    function bTokenExist(address) external view returns (bool);
    function bTokens(uint256) external view returns (address);
    function decreaseAssetsTotalBorrowed(string memory _assetName, uint256 _amount) external;
    function getAssetInfo(string memory _assetName) external view returns (Asset memory);
    function getAssetParameters(address _assetAddr)
        external
        view
        returns (uint256 liquidationThreshold, uint256 liquidationPenalty, uint256 loanToValue);
    function getAssetsNames() external view returns (string[] memory);
    function getAvailableTokensToBorrow(address _user) external view returns (uint256[] memory);
    function getAvailableTokensToRepay(address _user) external view returns (string[] memory, uint256[] memory);
    function getBTokens() external view returns (address[] memory);
    function getRewardsWeight(string memory assetName) external view returns (uint256);
    function increaseAccBTokensPerShare(string memory _assetName, uint256 _income) external;
    function increaseAccBorrowedRewardsPerShare(string memory _assetName, uint256 _assetRewards) external;
    function increaseAssetsTotalBorrowed(string memory _assetName, uint256 _amount) external;
    function initialize(address _pool, address _snastr) external;
    function owner() external view returns (address);
    function pool() external view returns (address);
    function removeAsset(string memory _assetName) external;
    function renounceOwnership() external;
    function setAdapter(address _adapter) external;
    function to18DecFormat(address _tokenAddress, uint256 _amount) external view returns (uint256);
    function toNativeDecFormat(address _tokenAddress, uint256 _amount) external view returns (uint256);
    function transferOwnership(address newOwner) external;
    function updateBalanceInAdaptersDistributor(address _user) external;
    function updateLastBTokenBalance(string memory _assetName) external;
}
