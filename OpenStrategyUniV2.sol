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
    function emergencyWithdraw(uint256 pid, address to) external;
    function rewarder(uint256 pid) external view returns (address);
}

contract UniswapV2Strategy {
    using SafeERC20 for IERC20;

    // Vault for strategy
    address public vault;

    // Tokens used
    address public native;
    address public reward;
    address public want;
    address public lpToken0;
    address public lpToken1;

    // Third party contracts
    address public chef;
    uint256 public poolId;

    uint256 public lastHarvest;

    // Fees
    uint256 public maxFee;

    uint256 public strategistFee;
    uint256 public stakerFee;
    uint256 public harvesterFee;

    // uint256 public performancePODLFee = 500;

    // Routes
    address[] public rewardToNativeRoute;
    address[] public nativeToLp0Route;
    address[] public nativeToLp1Route;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

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

        reward = _rewardToNativeRoute[0];
        native = _nativeToLp0Route[0];
        rewardToNativeRoute = _rewardToNativeRoute;

        require(_fees.length == 4, "invalid num of fees");
        require(_fees[0] >= _fees[1] + _fees[2] + _fees[3], "invalid fees");
        maxFee = _fees[0];
        strategistFee = _fees[1];
        harvesterFee = _fees[2];
        stakerFee = _fees[3];

        // setup lp routing
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
            IChef(chef).deposit(poolId, wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external payable {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IChef(chef).withdraw(poolId, _amount - wantBal);
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        IERC20(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    // compounds earnings and charges performance fee
    function harvest(address callFeeRecipient) public {
        IChef(chef).deposit(poolId, 0);
        uint256 rewardBal = IERC20(output).balanceOf(address(this));

        if (rewardBal > 0) {
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 toNative = IERC20(output).balanceOf(address(this)) * fees.total / DIVISOR;
        if (toNative > 0) {
            IUniswapRouter(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativeRoute, address(this), block.timestamp);
        }

        if (secondOutput != address(0)) {
            uint256 secondToNative = IERC20(secondOutput).balanceOf(address(this));
            if (secondToNative > 0) {
                IUniswapRouter(unirouter).swapExactTokensForTokens(secondToNative, 0, secondOutputToNativeRoute, address(this), block.timestamp);
            }
        }

        uint256 nativeBal = IERC20(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = nativeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFee);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFee);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 nativeHalf = IERC20(native).balanceOf(address(this)) / 2;

        if (lpToken0 != native) {
            IUniswapRouter(unirouter).swapExactTokensForTokens(nativeHalf, 0, nativeToLp0Route, address(this), block.timestamp);
        }

        if (lpToken1 != native) {
            IUniswapRouter(unirouter).swapExactTokensForTokens(nativeHalf, 0, nativeToLp1Route, address(this), block.timestamp);
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        IUniswapRouter(unirouter).addLiquidity(lpToken0, lpToken1, lp0Bal, lp1Bal, 1, 1, address(this), block.timestamp);
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
        (uint256 _amount,) = ISpookyChefV2(chef).userInfo(poolId, address(this));
        return _amount;
    }

    function rewardsAvailable() public view returns (uint256, uint256) {
        address rewarder = ISpookyChefV2(chef).rewarder(poolId);
        uint256 outputBal = ISpookyRewarder(rewarder).pendingToken(poolId, address(this));
        uint256 secondBal;
        if (secondOutput != address(0)) {
            secondBal = ISpookyChefV2(chef).pendingBOO(poolId, address(this));
        }

        return (outputBal, secondBal);
    }

    function callReward() public view returns (uint256) {
        IFeeConfig.FeeCategory memory fees = getFees();
        (uint256 outputBal, uint256 secondBal) = rewardsAvailable();
        uint256 nativeBal;

        try IUniswapRouter(unirouter).getAmountsOut(outputBal, outputToNativeRoute)
            returns (uint256[] memory amountOut)
        {
            nativeBal = nativeBal + amountOut[amountOut.length -1];
        }
        catch {}

        if (secondOutput != address(0)) {
            try IUniswapRouter(unirouter).getAmountsOut(secondBal, secondOutputToNativeRoute)
                returns (uint256[] memory amountOut)
            {
                nativeBal = nativeBal + amountOut[amountOut.length -1];
            }
            catch {}
        }

        return nativeBal * fees.total / DIVISOR * fees.call / DIVISOR;
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(chef, type(uint256).max);
        IERC20(output).safeApprove(unirouter, type(uint256).max);
        if (secondOutput != address(0)) {
            IERC20(secondOutput).safeApprove(unirouter, type(uint256).max);
        }
        IERC20(native).safeApprove(unirouter, type(uint256).max);

        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, type(uint256).max);

        IERC20(lpToken1).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, type(uint256).max);
    }

    function outputToNative() external view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function nativeToLp0() external view returns (address[] memory) {
        return nativeToLp0Route;
    }

    function nativeToLp1() external view returns (address[] memory) {
        return nativeToLp1Route;
    }
}
