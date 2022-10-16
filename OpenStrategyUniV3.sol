// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol";
import "https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/pool/IUniswapV3PoolActions.sol";
import "https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/IUniswapV3Pool.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/IERC721.sol";
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

// Originally INonfungiblePositionManager
interface IUniswapV3PositionsNFT is IERC721 {
    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    /// @notice Returns the position information associated with a given token ID.
    /// @dev Throws if the token ID is not valid.
    /// @param tokenId The ID of the token that represents the position
    /// @return nonce The nonce for permits
    /// @return operator The address that is approved for spending
    /// @return token0 The address of the token0 for a specific pool
    /// @return token1 The address of the token1 for a specific pool
    /// @return fee The fee associated with the pool
    /// @return tickLower The lower end of the tick range for the position
    /// @return tickUpper The higher end of the tick range for the position
    /// @return liquidity The liquidity of the position
    /// @return feeGrowthInside0LastX128 The fee growth of token0 as of the last action on the individual position
    /// @return feeGrowthInside1LastX128 The fee growth of token1 as of the last action on the individual position
    /// @return tokensOwed0 The uncollected amount of token0 owed to the position as of the last computation
    /// @return tokensOwed1 The uncollected amount of token1 owed to the position as of the last computation
    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce, // [0]
            address operator, // [1]
            address token0, // [2]
            address token1, // [3]
            uint24 fee, // [4]
            int24 tickLower, // [5]
            int24 tickUpper, // [6]
            uint128 liquidity, // [7]
            uint256 feeGrowthInside0LastX128, // [8]
            uint256 feeGrowthInside1LastX128, // [9]
            uint128 tokensOwed0, // [10]
            uint128 tokensOwed1 // [11]
        );

    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    /// @notice Decreases the amount of liquidity in a position and accounts it to the position
    /// @param params tokenId The ID of the token for which liquidity is being decreased,
    /// amount The amount by which liquidity will be decreased,
    /// amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
    /// amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
    /// deadline The time by which the transaction must be included to effect the change
    /// @return amount0 The amount of token0 accounted to the position's tokens owed
    /// @return amount1 The amount of token1 accounted to the position's tokens owed
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);

    /// @notice Collects up to a maximum amount of fees owed to a specific position to the recipient
    /// @param params tokenId The ID of the NFT for which tokens are being collected,
    /// recipient The account that should receive the tokens,
    /// amount0Max The maximum amount of token0 to collect,
    /// amount1Max The maximum amount of token1 to collect
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);

    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);

    function mint(MintParams calldata params)
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    function burn(uint256 tokenId) external payable;

    function refundETH() external payable;

    function unwrapWETH9(uint256 amountMinimum, address recipient) external payable;

    function sweepToken(
        address token,
        uint256 amountMinimum,
        address recipient
    ) external payable;
}

/// @title Router token swapping functionality
/// @notice Functions for swapping tokens via Uniswap V3
interface ISwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @dev Setting `amountIn` to 0 will cause the contract to look up its own balance,
    /// and swap the entire amount, enabling contracts to send tokens before calling this function.
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another along the specified path
    /// @dev Setting `amountIn` to 0 will cause the contract to look up its own balance,
    /// and swap the entire amount, enabling contracts to send tokens before calling this function.
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactInputParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInput(ExactInputParams calldata params)
        external
        payable
        returns (uint256 amountOut);

    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps as little as possible of one token for `amountOut` of another token
    /// that may remain in the router after the swap.
    /// @param params The parameters necessary for the swap, encoded as `ExactOutputSingleParams` in calldata
    /// @return amountIn The amount of the input token
    function exactOutputSingle(ExactOutputSingleParams calldata params)
        external
        payable
        returns (uint256 amountIn);

    struct ExactOutputParams {
        bytes path;
        address recipient;
        uint256 amountOut;
        uint256 amountInMaximum;
    }

    /// @notice Swaps as little as possible of one token for `amountOut` of another along the specified path (reversed)
    /// that may remain in the router after the swap.
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactOutputParams` in calldata
    /// @return amountIn The amount of the input token
    function exactOutput(ExactOutputParams calldata params)
        external
        payable
        returns (uint256 amountIn);
}

abstract contract StrategyRebalanceUniV3 {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    // using PoolVariables for IUniswapV3Pool;

    // Perfomance fees - start with 20%
    uint256 public performanceTreasuryFee = 2000;
    uint256 public constant performanceTreasuryMax = 10000;

    // User accounts
    address public strategist;

    // Dex
    address public constant univ3Router =
        0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    // Tokens
    IUniswapV3Pool public pool;

    IERC20 public token0;
    IERC20 public token1;
    uint256 public tokenId;

    int24 public tick_lower;
    int24 public tick_upper;
    int24 private tickSpacing;
    int24 private tickRangeMultiplier;
    uint24 public swapPoolFee;
    uint24 private twapTime = 60;

    IUniswapV3PositionsNFT public nftManager =
        IUniswapV3PositionsNFT(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    mapping(address => bool) public harvesters;

    event InitialDeposited(uint256 tokenId);
    event Harvested(uint256 tokenId);
    event Deposited(
        uint256 tokenId,
        uint256 token0Balance,
        uint256 token1Balance
    );
    event Withdrawn(uint256 tokenId, uint256 _liquidity);
    event Rebalanced(uint256 tokenId, int24 _tickLower, int24 _tickUpper);

    constructor(
        address _pool,
        int24 _tickRangeMultiplier,
        address _strategist
    ) public {
        strategist = _strategist;

        pool = IUniswapV3Pool(_pool);
        swapPoolFee = pool.fee();

        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());

        tickSpacing = pool.tickSpacing();
        tickRangeMultiplier = _tickRangeMultiplier;

        token0.safeApprove(address(nftManager), uint256(-1));
        token1.safeApprove(address(nftManager), uint256(-1));
    }

    // **** Views **** //

    function liquidityOfThis() public view returns (uint256) {
        uint256 liquidity = uint256(
            pool.liquidityForAmounts(
                token0.balanceOf(address(this)),
                token1.balanceOf(address(this)),
                tick_lower,
                tick_upper
            )
        );
        return liquidity;
    }

    function liquidityOfPool() public view returns (uint256) {
        (, , , , , , , uint128 _liquidity, , , , ) = nftManager.positions(
            tokenId
        );
        return _liquidity;
    }

    function liquidityOf() public view returns (uint256) {
        return liquidityOfThis().add(liquidityOfPool());
    }

    function getName() external pure virtual returns (string memory);

    // **** Setters **** //

    function setTwapTime(uint24 _twapTime) public {
        require(msg.sender == strategist, "!strategist");
        twapTime = _twapTime;
    }

    function setTickRangeMultiplier(int24 _tickRangeMultiplier) public {
        require(msg.sender == strategist, "!strategist");
        tickRangeMultiplier = _tickRangeMultiplier;
    }

    function amountsForLiquid() public view returns (uint256, uint256) {
        (uint256 a1, uint256 a2) = pool.amountsForLiquidity(
            1e18,
            tick_lower,
            tick_upper
        );
        return (a1, a2);
    }

    function determineTicks() public view returns (int24, int24) {
        uint32[] memory _observeTime = new uint32[](2);
        _observeTime[0] = twapTime;
        _observeTime[1] = 0;
        (int56[] memory _cumulativeTicks, ) = pool.observe(_observeTime);
        int56 _averageTick = (_cumulativeTicks[1] - _cumulativeTicks[0]) /
            twapTime;
        int24 baseThreshold = tickSpacing * tickRangeMultiplier;
        return
            pool.baseTicks(
                int24(_averageTick),
                baseThreshold,
                tickSpacing
            );
    }

    // **** State mutations **** //

    function deposit() public {
        uint256 _token0 = token0.balanceOf(address(this));
        uint256 _token1 = token1.balanceOf(address(this));

        if (_token0 > 0 && _token1 > 0) {
            nftManager.increaseLiquidity(
                IUniswapV3PositionsNFT.IncreaseLiquidityParams({
                    tokenId: tokenId,
                    amount0Desired: _token0,
                    amount1Desired: _token1,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 300
                })
            );
        }

        emit Deposited(tokenId, _token0, _token1);
    }

    function _withdrawSome(uint256 _liquidity)
        internal
        returns (uint256, uint256)
    {
        if (_liquidity == 0) return (0, 0);

        (uint256 _a0Expect, uint256 _a1Expect) = pool.amountsForLiquidity(
            uint128(_liquidity),
            tick_lower,
            tick_upper
        );
        (uint256 amount0, uint256 amount1) = nftManager.decreaseLiquidity(
            IUniswapV3PositionsNFT.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: uint128(_liquidity),
                amount0Min: _a0Expect,
                amount1Min: _a1Expect,
                deadline: block.timestamp + 300
            })
        );

        //Only collect decreasedLiquidity, not trading fees.
        nftManager.collect(
            IUniswapV3PositionsNFT.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: uint128(amount0),
                amount1Max: uint128(amount1)
            })
        );

        return (amount0, amount1);
    }

    function withdraw(uint256 _liquidity)
        external
        returns (uint256 a0, uint256 a1)
    {
        require(msg.sender == vault, "!vault");
        (a0, a1) = _withdrawSome(_liquidity);

        address _vault = IVault(vault).vaults(address(pool));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds

        token0.safeTransfer(_vault, a0);
        token1.safeTransfer(_vault, a1);

        emit Withdrawn(tokenId, _liquidity);
    }

    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint256 a0, uint256 a1) {
        require(msg.sender == vault, "!vault");
        _withdrawAll();
        address _vault = IControllerV2(controller).vaults(address(pool));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds

        a0 = token0.balanceOf(address(this));
        a1 = token1.balanceOf(address(this));
        token0.safeTransfer(_vault, a0);
        token1.safeTransfer(_vault, a1);
    }

    function _withdrawAll() internal returns (uint256 a0, uint256 a1) {
        (a0, a1) = _withdrawSome(liquidityOfPool());
    }

    function harvest() public {
        uint256 _initToken0 = token0.balanceOf(address(this));
        uint256 _initToken1 = token1.balanceOf(address(this));
        nftManager.collect(
            IUniswapV3PositionsNFT.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        nftManager.sweepToken(address(token0), 0, address(this));
        nftManager.sweepToken(address(token1), 0, address(this));

        _distributePerformanceFees(
            token0.balanceOf(address(this)).sub(_initToken0),
            token1.balanceOf(address(this)).sub(_initToken1)
        );

        _balanceProportion(tick_lower, tick_upper);

        deposit();

        emit Harvested(tokenId);
    }

    function getHarvestable() public returns (uint256, uint256) {
        //This will only update when someone mint/burn/pokes the pool.
        (uint256 _owed0, uint256 _owed1) = nftManager.collect(
            IUniswapV3PositionsNFT.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        return (uint256(_owed0), uint256(_owed1));
    }

    function rebalance() external returns (uint256 _tokenId) {
        if (tokenId != 0) {
            uint256 _initToken0 = token0.balanceOf(address(this));
            uint256 _initToken1 = token1.balanceOf(address(this));
            (, , , , , , , uint256 _liquidity, , , , ) = nftManager.positions(
                tokenId
            );
            (uint256 _liqAmt0, uint256 _liqAmt1) = nftManager.decreaseLiquidity(
                IUniswapV3PositionsNFT.DecreaseLiquidityParams({
                    tokenId: tokenId,
                    liquidity: uint128(_liquidity),
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 300
                })
            );

            // This has to be done after DecreaseLiquidity to collect the tokens we
            // decreased and the fees at the same time.
            nftManager.collect(
                IUniswapV3PositionsNFT.CollectParams({
                    tokenId: tokenId,
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );

            nftManager.sweepToken(address(token0), 0, address(this));
            nftManager.sweepToken(address(token1), 0, address(this));
            nftManager.burn(tokenId);

            _distributePerformanceFees(
                token0.balanceOf(address(this)).sub(_liqAmt0).sub(_initToken0),
                token1.balanceOf(address(this)).sub(_liqAmt1).sub(_initToken1)
            );
        }

        (int24 _tickLower, int24 _tickUpper) = determineTicks();
        _balanceProportion(_tickLower, _tickUpper);
        //Need to do this again after the swap to cover any slippage.
        uint256 _amount0Desired = token0.balanceOf(address(this));
        uint256 _amount1Desired = token1.balanceOf(address(this));

        (_tokenId, , , ) = nftManager.mint(
            IUniswapV3PositionsNFT.MintParams({
                token0: address(token0),
                token1: address(token1),
                fee: pool.fee(),
                tickLower: _tickLower,
                tickUpper: _tickUpper,
                amount0Desired: _amount0Desired,
                amount1Desired: _amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 300
            })
        );

        //Record updated information.
        tokenId = _tokenId;
        tick_lower = _tickLower;
        tick_upper = _tickUpper;

        if (tokenId == 0) {
            emit InitialDeposited(_tokenId);
        }

        emit Rebalanced(tokenId, _tickLower, _tickUpper);
    }

    // **** Emergency functions ****

    function execute(address _target, bytes memory _data)
        public
        payable
        returns (bytes memory response)
    {
        require(msg.sender == timelock, "!timelock");
        require(_target != address(0), "!target");

        // call contract in current context
        assembly {
            let succeeded := delegatecall(
                sub(gas(), 5000),
                _target,
                add(_data, 0x20),
                mload(_data),
                0,
                0
            )
            let size := returndatasize()

            response := mload(0x40)
            mstore(
                0x40,
                add(response, and(add(add(size, 0x20), 0x1f), not(0x1f)))
            )
            mstore(response, size)
            returndatacopy(add(response, 0x20), 0, size)

            switch iszero(succeeded)
            case 1 {
                // throw if delegatecall failed
                revert(add(response, 0x20), size)
            }
        }
    }

    // **** Internal functions ****
    function _balanceProportion(int24 _tickLower, int24 _tickUpper) internal {
        pool.Info memory _cache;

        _cache.amount0Desired = token0.balanceOf(address(this));
        _cache.amount1Desired = token1.balanceOf(address(this));

        //Get Max Liquidity for Amounts we own.
        _cache.liquidity = pool.liquidityForAmounts(
            _cache.amount0Desired,
            _cache.amount1Desired,
            _tickLower,
            _tickUpper
        );

        //Get correct amounts of each token for the liquidity we have.
        (_cache.amount0, _cache.amount1) = pool.amountsForLiquidity(
            _cache.liquidity,
            _tickLower,
            _tickUpper
        );

        //Determine Trade Direction
        bool _zeroForOne;
        if (_cache.amount1Desired == 0) {
            _zeroForOne = true;
        } else {
            _zeroForOne = pool.amountsDirection(
                _cache.amount0Desired,
                _cache.amount1Desired,
                _cache.amount0,
                _cache.amount1
            );
        }

        //Determine Amount to swap
        uint256 _amountSpecified = _zeroForOne
            ? (_cache.amount0Desired.sub(_cache.amount0).div(2))
            : (_cache.amount1Desired.sub(_cache.amount1).div(2));

        if (_amountSpecified > 0) {
            //Determine Token to swap
            address _inputToken = _zeroForOne
                ? address(token0)
                : address(token1);

            IERC20(_inputToken).safeApprove(univ3Router, 0);
            IERC20(_inputToken).safeApprove(univ3Router, _amountSpecified);

            //Swap the token imbalanced
            ISwapRouter02(univ3Router).exactInputSingle(
                ISwapRouter02.ExactInputSingleParams({
                    tokenIn: _inputToken,
                    tokenOut: _zeroForOne ? address(token1) : address(token0),
                    fee: swapPoolFee,
                    recipient: address(this),
                    amountIn: _amountSpecified,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        }
    }

    function _distributePerformanceFees(uint256 _amount0, uint256 _amount1)
        internal
    {
        if (_amount0 > 0) {
            IERC20(token0).safeTransfer(
                IControllerV2(controller).treasury(),
                _amount0.mul(performanceTreasuryFee).div(performanceTreasuryMax)
            );
        }
        if (_amount1 > 0) {
            IERC20(token1).safeTransfer(
                IControllerV2(controller).treasury(),
                _amount1.mul(performanceTreasuryFee).div(performanceTreasuryMax)
            );
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract StrategyWbtcEthUniV3 is StrategyRebalanceUniV3 {
    address private priv_pool = 0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0;

    constructor(
        int24 _tickRangeMultiplier,
        uint24 _swapPoolFee,
        address _governance,
        address _strategist,
        address _controller,
        address _timelock
    )
        public
        StrategyRebalanceUniV3(
            priv_pool,
            _tickRangeMultiplier,
            _governance,
            _strategist,
            _controller,
            _timelock
        )
    {
        swapPoolFee = (_swapPoolFee != 0) ? _swapPoolFee : pool.fee();
    }

    function getName() external pure override returns (string memory) {
        return "StrategyWbtcEthUniV3";
    }
}