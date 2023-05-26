//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "../lib/openzeppelin-contracts-upgradeable/contracts/utils/AddressUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IERC20Plus.sol";
import "./interfaces/DappsStaking.sol";
import "./ALGMVesting.sol";
import "./libraries/ByteConversion.sol";

/* 
before deploy:
- change some vars to constant (tokens, liquid)
 */

contract LiquidCrowdloan is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using AddressUpgradeable for address payable;
    using AddressUpgradeable for address;
    using ByteConversion for bytes3;

    ALGMVesting public vesting;

    bool public closed;

    address public liquidStakingAddr;

    uint256 public totalStaked;
    uint256 public crowdLoanCloseTime;

    // to remove after test
    uint256 public MIN_AMOUNT = 100 * 1e18;
    uint256 public MAX_AMOUNT = 100_000_000 * 1e18;
    uint256 public ALGM_REWARDS_AMOUNT = 2_500_000 * 1e18;

    // ==> uncomment back after test // uint256 public constant MIN_AMOUNT = 100 * 1e18; // 100 ASTR min deposit
    // ==> uncomment back after test // uint256 public constant MAX_AMOUNT = 100_000_000 * 1e18; // 100M ASTR max deposit
    uint256 private constant SHARE_PRECISION = 1e18;
    uint256 private constant ONE_MONTH = 30 days;
    uint256 public withdrawBlock;
    uint256 public lastUnstaked;
    uint256 public sumToUnstake;
    uint256 public unbondedPool;
    uint256 public lastStakingRewardsClaimedEra;
    uint256 public claimingTxLimit;
    uint256 public totalStakingRewards;

    // need to clarify the exact amount of algm rewards (1.5 - 2.5 kk)
    // ==> uncomment back after test // uint256 public constant ALGM_REWARDS_AMOUNT = 2_500_000 * 1e18; // amount of ALGM rewards

    IERC20Plus public aastr;
    IERC20Plus public algm;
    DappsStaking public dappsStaking;

    address[] public stakers;

    mapping(address => bool) public isStaker; // unused var, consider to remove
    mapping(address => uint256) public stakes;
    mapping(address => uint256) public userClaimedSlices;
    mapping(address => Withdrawal[]) public withdrawals;
    mapping(address => bool) public isRefUsedByAddress;
    mapping(string => bool) public isActiveRef;
    mapping(string => address) public refToOwner;
    mapping(address => string) public addrToUsedRef;
    mapping(address => string) public ownerToRef;

    struct VestingParams {
        address beneficiary;
        uint256 cliff;
        uint256 startTime;
        uint256 duration;
        uint256 slicePeriod;
        bool revocable;
        uint256 amount;
    }

    VestingParams public vestingParams;

    struct Withdrawal {
        uint256 val;
        uint256 eraReq;
        uint256 lag;
    }

    event UnbondAndUnstakeError(
        uint256 indexed sum2unstake,
        uint256 indexed era,
        bytes indexed reason
    );
    event UnbondAndUnstakeSuccess(uint256 indexed era, uint256 sum2unstake);
    event Withdrawn(address indexed user, uint256 val);
    event WithdrawUnbondedError(uint256 indexed _era, bytes indexed reason);
    event WithdrawUnbondedSuccess(uint256 indexed _era);
    event SetClaimingTxLimit(address indexed sender, uint256 indexed val);
    event ClaimStakerSuccess(uint256 indexed era, uint256 lastClaimed);
    event ClaimStakerError(uint256 indexed era, bytes indexed reason);
    event WithdrawStakingRewards(address indexed user, uint256 amount);
    event Stake(address indexed user, uint256 amount, string indexed refCode);
    event CloseCrowdloanAndStartVesting(uint256 closeTime);
    event ClaimRewards(address user, uint256 rewardsToClaim);
    event Unstake(
        address indexed user,
        uint256 indexed amount,
        uint256 indexed era
    );
    event GlobalUnstake(
        address indexed who,
        uint256 indexed era,
        uint256 indexed sumToUnstake
    );
    event GlobalWithdraw(
        address indexed who,
        uint256 indexed era,
        uint256 amount
    );
    event ClaimDappsStakingRewards(uint256 indexed era, uint256 amount);

    // /// @custom:oz-upgrades-unsafe-allow constructor
    // constructor() {
    //     _disableInitializers();
    // }

    function initialize(
        ALGMVesting _vesting,
        address _liquidStakingAddr,
        address _aastr,
        address _algm,
        address _dappsStaking
    ) public initializer {
        __Ownable_init();

        aastr = IERC20Plus(_aastr); // IERC20Plus(0xffFffffF0000000000000000000000000000052E); 1326
        algm = IERC20Plus(_algm); // IERC20Plus(0xFFfFFFFF00000000000000000000000000000530); 1328
        dappsStaking = DappsStaking(_dappsStaking); //DappsStaking(0x0000000000000000000000000000000000005001);

        vesting = _vesting;
        liquidStakingAddr = _liquidStakingAddr;

        vestingParams = VestingParams({
            beneficiary: address(this),
            cliff: 7 days,
            startTime: block.timestamp,
            duration: 6 * 30 days,
            slicePeriod: 7 days,
            revocable: true,
            amount: ALGM_REWARDS_AMOUNT
        });

        withdrawBlock = dappsStaking.read_unbonding_period();
        lastUnstaked = currentEra() - 1;
        lastStakingRewardsClaimedEra = currentEra();
        setClaimingTxLimit(5);
    }

    modifier notClosed() {
        require(!closed, "Crowdloan closed");
        _;
    }

    // Needed for tests and will be removed on production
    receive() external payable {
        // require(msg.sender == address(dappsStaking), "Not allowed");
    }

    // @notice Deposit ASTR and get aASTR
    function stake() public payable notClosed {
        stake("");
    }

    // @notice Deposit ASTR and get aASTR
    // @param _ref Referral code
    function stake(string memory _ref) public payable notClosed {
        (uint256 amount, address user) = (msg.value, msg.sender);
        require(amount >= MIN_AMOUNT, "Need more ASTR");
        require(totalStaked + amount <= MAX_AMOUNT, "Too large deposit");
        require(
            !isRefUsedByAddress[msg.sender],
            "Referral codes have already been used by user"
        );

        if (
            keccak256(abi.encodePacked(_ref)) != keccak256(abi.encodePacked(""))
        ) {
            require(isActiveRef[_ref], "Referral code is not active");

            isActiveRef[_ref] = false;
            isRefUsedByAddress[msg.sender] = true;
            addrToUsedRef[msg.sender] = _ref;
        }

        stakes[user] += amount;
        totalStaked += amount;

        /* to remove after testing */ dappsStaking.bond_and_stake{value: msg.value}(liquidStakingAddr, uint128(amount));
        // dappsStaking.bond_and_stake(liquidStakingAddr, uint128(amount));

        if (!isStaker[user]) {
            isStaker[user] = true;
            stakers.push(user);
        }

        require(aastr.mint(user, amount), "Error during mint aASTR");

        emit Stake(msg.sender, msg.value, _ref);
    }

    // @notice Crowdloan closing and start vesting period
    function closeCrowdloan() external notClosed onlyOwner {
        closed = true;
        crowdLoanCloseTime = block.timestamp;

        vesting.createVesting(
            address(this),
            vestingParams.cliff,
            block.timestamp,
            vestingParams.duration,
            vestingParams.slicePeriod,
            vestingParams.revocable,
            vestingParams.amount
        );

        emit CloseCrowdloanAndStartVesting(block.timestamp);
    }

    // @notice Claim available ALGM tokens by users
    function claimRewards() public nonReentrant {
        uint256 rewards = getUserAvailableRewards(msg.sender);
        require(rewards > 0, "User has no any rewards");

        uint256 rewardsToClaim = getTotalAvailableRewards();

        if (rewardsToClaim > 0) {
            // claim algm tokens from vesting contract if any
            vesting.claim(_getVestingId(), rewardsToClaim);
        }

        userClaimedSlices[msg.sender] = slicesPassed();
        
        algm.transfer(msg.sender, rewards);

        emit ClaimRewards(msg.sender, rewardsToClaim);
    }

    // @notice Unstake ASTR after vesting period ends
    //         and put it to user's withdrawals or unstake
    //         immediately if possible
    function unstake() public {
        uint256 amount = aastr.balanceOf(msg.sender);

        require(amount > 0, "User has no any aASTR");
        require(crowdLoanCloseTime != 0, "Crowdloan still open");
        require(
            crowdLoanCloseTime + vestingParams.duration <= block.timestamp,
            "Locking period has not yet passed"
        );

        uint256 era = currentEra();
        sumToUnstake += amount;
        totalStaked -= amount;

        require(
            aastr.balanceOf(msg.sender) >= amount,
            "Not enough tokens to burn"
        );
        aastr.burn(msg.sender, amount);

        uint256 lag;
        if (lastUnstaked * 10 + (withdrawBlock * 10) / 4 > era * 10) {
            lag = lastUnstaked * 10 + (withdrawBlock * 10) / 4 - era * 10;
        }
        // create a withdrawal to withdraw_unbonded later
        withdrawals[msg.sender].push(
            Withdrawal({val: amount, eraReq: era, lag: lag})
        );

        _globalUnstake();

        emit Unstake(msg.sender, amount, era);
    }

    // @notice Withdraw ASTR stake after its unbonding period
    // @param _id index of user's Withdrawal in withdrawals
    function withdraw(uint256 _id) external {
        _globalWithdraw(currentEra());
        Withdrawal storage withdrawal = withdrawals[msg.sender][_id];
        uint256 val = withdrawal.val;

        require(withdrawal.eraReq != 0, "Withdrawal already claimed");
        require(
            currentEra() * 10 - withdrawal.eraReq * 10 >=
                withdrawBlock * 10 + withdrawal.lag,
            "Not enough eras passed!"
        );
        require(unbondedPool >= val, "Not enough funds in unbonded pool");

        unbondedPool -= val;
        withdrawal.eraReq = 0;

        payable(msg.sender).sendValue(val);

        emit Withdrawn(msg.sender, val);
    }

    function _globalUnstake() private {
        uint256 era = currentEra();

        // checks if enough time has passed
        if (era * 10 < lastUnstaked * 10 + (withdrawBlock * 10) / 4) {
            return;
        }

        if (sumToUnstake > 0) {
            try
                dappsStaking.unbond_and_unstake(
                    address(this),
                    uint128(sumToUnstake)
                )
            {
                emit UnbondAndUnstakeSuccess(era, sumToUnstake);
                sumToUnstake = 0;
                lastUnstaked = era;
            } catch (bytes memory reason) {
                emit UnbondAndUnstakeError(sumToUnstake, era, reason);
            }
        }

        emit GlobalUnstake(msg.sender, era, sumToUnstake);
    }

    function _globalWithdraw(uint256 _era) private {
        uint256 balBefore = address(this).balance;

        try dappsStaking.withdraw_unbonded() {
            emit WithdrawUnbondedSuccess(_era);
        } catch (bytes memory reason) {
            emit WithdrawUnbondedError(_era, reason);
        }

        uint256 balAfter = address(this).balance;
        unbondedPool += balAfter - balBefore;

        emit GlobalWithdraw(msg.sender, _era, balAfter - balBefore);
    }

    // @notice Claim staking rewards by the owner
    function claimDappStakingRewards() public onlyOwner {
        uint256 era = currentEra();
        require(
            lastStakingRewardsClaimedEra != era,
            "All rewards already claimed"
        );

        uint256 numOfUnclaimedEras = era - lastStakingRewardsClaimedEra;
        if (numOfUnclaimedEras > claimingTxLimit) {
            numOfUnclaimedEras = claimingTxLimit;
        }
        uint256 balBefore = address(this).balance;

        // get unclaimed rewards
        for (uint256 i; i < numOfUnclaimedEras; i++) {
            try dappsStaking.claim_staker(liquidStakingAddr) {
                lastStakingRewardsClaimedEra += 1;
                emit ClaimStakerSuccess(era, lastStakingRewardsClaimedEra);
            } catch (bytes memory reason) {
                emit ClaimStakerError(lastStakingRewardsClaimedEra + 1, reason);
            }
        }

        uint256 balAfter = address(this).balance;

        totalStakingRewards += balAfter - balBefore;

        emit ClaimDappsStakingRewards(era, balAfter - balBefore);
    }

    // @notice Withdraw staking rewards by the owner
    function withdrawStakingRewardsAdmin() external onlyOwner {
        uint256 amount = totalStakingRewards;
        totalStakingRewards = 0;
        payable(msg.sender).sendValue(amount);

        emit WithdrawStakingRewards(msg.sender, amount);
    }

    // @notice For manually global unstake
    function globalUnstakeAdmin() external onlyOwner {
        require(sumToUnstake > 0, "No any unstakes");
        require(
            currentEra() * 10 >= lastUnstaked * 10 + (withdrawBlock * 10) / 4,
            "There was already globalUnstake in this period of time"
        );
        _globalUnstake();
    }

    // @notice Limits the maximum number of iterations in the loop when claiming rewards
    // @param _val Number of iters
    function setClaimingTxLimit(uint256 _val) public onlyOwner {
        claimingTxLimit = _val;

        emit SetClaimingTxLimit(msg.sender, _val);
    }

    // @notice To become a referrer
    function becomeReferrer() public returns (string memory ref) {
        address user = msg.sender;
        require(keccak256(abi.encodePacked(ownerToRef[user])) != keccak256(""), "User is already a referrer");

        bytes3 data = bytes3(keccak256(abi.encode(user, block.timestamp)));
        string memory ref = data.toString();

        isActiveRef[ref] = true;
        refToOwner[ref] = user;
        ownerToRef[msg.sender] = ref;
    }

    // @notice Get total available rewards for Crowdloan contract
    // @return Number of rewards
    function getTotalAvailableRewards() public view returns (uint256) {
        return vesting.computeReleasableAmount(_getVestingId());
    }

    // @notice Get user's available rewards
    // @param _user User address
    // @return Number of rewards
    function getUserAvailableRewards(
        address _user
    ) public view returns (uint256) {
        if (slicesPassed() <= userClaimedSlices[_user]) return 0;
        uint256 slicesToClaim = slicesPassed() - userClaimedSlices[_user];
        return
            (((_userShare(_user) * ALGM_REWARDS_AMOUNT) / SHARE_PRECISION) *
                slicesToClaim *
                vestingParams.slicePeriod) / vestingParams.duration;
    }

    function _getVestingId() private view returns (bytes32) {
        uint256 lastVestingId = vesting.holdersVestingCount(address(this)) - 1;
        return vesting.computeVestingIdForAddressAndIndex(address(this), lastVestingId);
    }

    // @notice Get the number of passed slices since the vesting period started
    // @return Number of slices
    function slicesPassed() public view returns (uint256) {
        require(
            crowdLoanCloseTime != 0 && block.timestamp >= crowdLoanCloseTime,
            "Vesting period has not started yet"
        );
        uint256 passed = (block.timestamp - crowdLoanCloseTime) /
            vestingParams.slicePeriod;
        uint256 maxSliceAmount = vestingParams.duration /
            vestingParams.slicePeriod;
        if (passed > maxSliceAmount) return maxSliceAmount;
        return passed;
    }

    function _userShare(address _user) private view returns (uint256) {
        return (stakes[_user] * SHARE_PRECISION) / totalStaked;
    }

    // @notice Get stakers array
    // @return Address array
    function getStakers() public view returns (address[] memory) {
        return stakers;
    }

    // @notice Get current era
    // @return Current era number
    function currentEra() public view returns (uint256) {
        return dappsStaking.read_current_era();
    }

    ////////////////////////////////////////////////////////////////////////////
    //
    // FOR TESTS
    //
    ////////////////////////////////////////////////////////////////////////////

    function setDappsStakingAddress(address addr) public onlyOwner {
        dappsStaking = DappsStaking(addr);
    }

    function setMaxMinAmounts(
        uint256 _maxAmount,
        uint256 _minAmount
    ) public onlyOwner {
        MAX_AMOUNT = _maxAmount;
        MIN_AMOUNT = _minAmount;
    }

    function setLockingPeriod(uint256 _lockingPeriod) public onlyOwner {
        vestingParams.duration = _lockingPeriod;
    }

    function setALGMRewardsAmount(uint256 _amount) public onlyOwner {
        ALGM_REWARDS_AMOUNT = _amount;
    }

    function resetData() public onlyOwner {
        for (uint256 i; i < stakers.length; i++) {
            isStaker[stakers[i]] = false;
            stakes[stakers[i]] = 0;
        }
        delete stakers;
        totalStaked = 0;
        closed = false;
        crowdLoanCloseTime = 0;
        lastStakingRewardsClaimedEra = currentEra();
        lastUnstaked = currentEra() - 1;
        sumToUnstake = 0;
        delete vestingParams;
        userClaimedSlices[msg.sender] = 0;
        stakes[msg.sender] = 0;
    }

    function switchClosed() public onlyOwner {
        closed = !closed;
    }

    function setVestingParams(
        uint256 _cliff,
        uint256 _duration,
        uint256 _slicePeriod,
        bool _revocable,
        uint256 _amount
    ) public onlyOwner {
        vestingParams.cliff = _cliff;
        vestingParams.duration = _duration;
        vestingParams.slicePeriod = _slicePeriod;
        vestingParams.revocable = _revocable;
        vestingParams.amount = _amount;
    }

    function mintToken(address to, uint256 amount) public onlyOwner {
        aastr.mint(to, amount);
    }

    function burnToken(address to, uint256 amount) public onlyOwner {
        aastr.burn(to, amount);
    }

    function sendALGM(address to, uint256 amount) public onlyOwner {
        algm.transfer(to, amount);
    }
}