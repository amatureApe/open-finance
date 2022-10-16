// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";


interface IUniswapRouter {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function totalSupply() external view returns (uint256);
}

interface IChef {
    function poolLength() external view returns (uint256);
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);
    function pendingSushi(uint256 _pid, address _user) external view returns (uint256);
    function deposit(uint256 pid, uint256 amount, address to) external;
    function withdraw(uint256 pid, uint256 amount, address to) external;
    function harvest(uint256 pid, address to) external;
    function withdrawAndHarvest(uint256 pid, uint256 amount, address to) external;
    function rewarder(uint256 pid) external view returns (address);
}

contract UniswapV2Strategy {
    using SafeERC20 for IERC20;

    // Vault addresses
    address public vault;
    address public strategist;

    // Tokens used
    address public native;
    address public reward;
    address public secondReward;
    address public want;
    address public lpToken0;
    address public lpToken1;

    // Third party contracts
    address public chef;
    uint256 public poolId;
    address public router;

    uint256 public lastHarvest;

    // Fees
    uint256 public maxFee;
    uint256 public strategistFee;
    uint256 public harvesterFee;
    uint256 private constant FEE_DIVISOR = 10000;

    // Routes
    address[] public rewardToNativeRoute;
    address[] public nativeToLp0Route;
    address[] public nativeToLp1Route;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 strategistFees, uint256 harvesterFee);

    constructor(
        address _vault,
        address _want,
        uint256 _poolId,
        address _chef,
        address _router,
        address _strategist,
        uint256[] memory _fees,
        address[] memory _rewardToNativeRoute,
        address[] memory _nativeToLp0Route,
        address[] memory _nativeToLp1Route
    ) {
        vault = _vault;
        want = _want;
        poolId = _poolId;
        chef = _chef;
        router = _router;
        strategist = _strategist;

        reward = _rewardToNativeRoute[0];
        native = _nativeToLp0Route[0];
        rewardToNativeRoute = _rewardToNativeRoute;

        require(_fees.length == 3, "invalid num of fees");
        require(_fees[0] >= _fees[1] + _fees[2], "invalid fees");
        maxFee = _fees[0];
        strategistFee = _fees[1];
        harvesterFee = _fees[2];

        // // setup lp routing
        lpToken0 = IUniswapV2Pair(want).token0();
        require(_nativeToLp0Route[0] == native, "nativeToLp0Route[0] != native");
        require(_nativeToLp0Route[_nativeToLp0Route.length - 1] == lpToken0, "nativeToLp0Route[last] != lpToken0");
        nativeToLp0Route = _nativeToLp0Route;

        lpToken1 = IUniswapV2Pair(want).token1();
        require(_nativeToLp1Route[0] == native, "nativeToLp1Route[0] != native");
        require(_nativeToLp1Route[_nativeToLp1Route.length - 1] == lpToken1, "nativeToLp1Route[last] != lpToken1");
        nativeToLp1Route = _nativeToLp1Route;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IChef(chef).deposit(poolId, wantBal, address(this));
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external payable {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IChef(chef).withdraw(poolId, _amount - wantBal, address(this));
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        IERC20(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    // compounds earnings and charges performance fee
    function harvest(address harvester) public {
        IChef(chef).harvest(poolId, address(this));
        uint256 rewardBal = IERC20(reward).balanceOf(address(this));

        if (rewardBal > 0) {
            chargeFees(harvester);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // function testHarvest1() public {
    //     IChef(chef).harvest(poolId, address(this));
    // }

    // function testHarvest2() public view returns (uint) {
    //     uint256 rewardBal = IERC20(reward).balanceOf(address(this));
    //     return rewardBal;
    // }

    // function testHarvest3(address harvester) public {
    //     chargeFees(harvester);
    // }

    // function testHarvest4() public {
    //     addLiquidity();
    // }

    // function testHarvest5() public view returns (uint) {
    //     uint256 wantHarvested = balanceOfWant();
    //     return wantHarvested;
    // }

    // function testHarvest6() public {
    //     deposit();
    // }

    // performance fees
    function chargeFees(address harvester) internal {
        uint256 toNative = IERC20(reward).balanceOf(address(this));
        if (toNative > 0) {
            IUniswapRouter(router).swapExactTokensForTokens(toNative, 0, rewardToNativeRoute, address(this), block.timestamp);
        }

        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        uint256 strategistAmount = nativeBal * strategistFee / maxFee;
        uint256 harvesterAmount = nativeBal * harvesterFee / maxFee;

        IERC20(native).safeTransfer(strategist, strategistAmount);
        IERC20(native).safeTransfer(harvester, harvesterAmount);

        emit ChargedFees(strategistFee, harvesterFee);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 nativeHalf = IERC20(native).balanceOf(address(this)) / 2;

        if (lpToken0 != native) {
            IUniswapRouter(router).swapExactTokensForTokens(nativeHalf, 0, nativeToLp0Route, address(this), block.timestamp);
        }

        if (lpToken1 != native) {
            IUniswapRouter(router).swapExactTokensForTokens(nativeHalf, 0, nativeToLp1Route, address(this), block.timestamp);
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        IUniswapRouter(router).addLiquidity(lpToken0, lpToken1, lp0Bal, lp1Bal, 1, 1, address(this), block.timestamp);
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        (uint256 _amount,) = IChef(chef).userInfo(poolId, address(this));
        return _amount;
    }

    function rewardsAvailable() public view returns (uint256) {
        uint256 rewardBal = IChef(chef).pendingSushi(poolId, address(this));

        return rewardBal;
    }

    function callReward() public view returns (uint256) {
        uint rewardBal = rewardsAvailable();
        uint256 nativeBal;

        try IUniswapRouter(router).getAmountsOut(rewardBal, rewardToNativeRoute)
            returns (uint256[] memory amountOut)
        {
            nativeBal = nativeBal + amountOut[amountOut.length -1];
        }
        catch {}

        return nativeBal * (strategistFee + harvesterFee) / maxFee;
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(chef, type(uint256).max);
        IERC20(reward).safeApprove(router, type(uint256).max);
        if (secondReward != address(0)) {
            IERC20(secondReward).safeApprove(router, type(uint256).max);
        }
        IERC20(native).safeApprove(router, type(uint256).max);

        IERC20(lpToken0).safeApprove(router, 0);
        IERC20(lpToken0).safeApprove(router, type(uint256).max);

        IERC20(lpToken1).safeApprove(router, 0);
        IERC20(lpToken1).safeApprove(router, type(uint256).max);
    }

    function rewardToNative() external view returns (address[] memory) {
        return rewardToNativeRoute;
    }

    function nativeToLp0() external view returns (address[] memory) {
        return nativeToLp0Route;
    }

    function nativeToLp1() external view returns (address[] memory) {
        return nativeToLp1Route;
    }
}
