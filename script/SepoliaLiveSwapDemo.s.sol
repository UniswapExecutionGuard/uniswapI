// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {UniswapExeGuard} from "../src/UniswapExeGuard.sol";
import {IPoolManager} from "../lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "../lib/v4-core/src/types/PoolKey.sol";
import {Currency} from "../lib/v4-core/src/types/Currency.sol";
import {IHooks} from "../lib/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "../lib/v4-core/src/libraries/TickMath.sol";
import {IERC20Minimal} from "../lib/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {PoolModifyLiquidityTest} from "../lib/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "../lib/v4-core/src/test/PoolSwapTest.sol";
import {TestERC20} from "../lib/v4-core/src/test/TestERC20.sol";

contract SepoliaLiveSwapDemo is Script {
    struct Config {
        address owner;
        address poolManager;
        address policyRegistry;
        address hook;
        uint256 tokenMint;
        uint256 liquidityDelta;
        uint256 allowedInput;
        uint256 blockedInput;
        uint256 maxSwapAbs;
        uint256 cooldownSeconds;
        uint24 fee;
        int24 tickSpacing;
        int24 tickLower;
        int24 tickUpper;
    }

    struct Result {
        address modifyRouter;
        address swapRouter;
        address token0;
        address token1;
        bool allowedSuccess;
        bool blockedSuccess;
        bytes blockedReturndata;
    }

    error OwnerMissing();
    error RegistryOwnerMismatch(address expected, address actual);
    error HookOwnerMismatch(address expected, address actual);
    error InvalidTickRange(int24 tickLower, int24 tickUpper);
    error InvalidTickSpacing(int24 tickSpacing, int24 tickLower, int24 tickUpper);
    error AllowedSwapFailed(bytes returndata);
    error BlockedSwapUnexpectedlySucceeded();

    function run() external {
        Config memory cfg = _loadConfig();
        _validateConfig(cfg);
        _validateOwners(cfg);

        vm.startBroadcast();
        Result memory res = _execute(cfg);
        vm.stopBroadcast();

        _simulateBlockedSwap(cfg, res);

        _logResult(cfg, res);
    }

    function _execute(Config memory cfg) internal returns (Result memory res) {
        IPoolManager manager = IPoolManager(cfg.poolManager);
        PoolModifyLiquidityTest modifyRouter = new PoolModifyLiquidityTest(manager);
        PoolSwapTest swapRouter = new PoolSwapTest(manager);
        (Currency currency0, Currency currency1, IERC20Minimal token0, IERC20Minimal token1) =
            _deploySortedTokens(cfg.tokenMint);

        PoolKey memory key = _buildKey(cfg, currency0, currency1);
        _initializeAndFundPool(cfg, manager, key, token0, token1, modifyRouter, swapRouter);
        PolicyRegistry(cfg.policyRegistry).setPolicy(cfg.owner, cfg.maxSwapAbs, cfg.cooldownSeconds);

        IPoolManager.SwapParams memory allowedParams = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(cfg.allowedInput),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        bytes memory allowedReturndata;
        (res.allowedSuccess, allowedReturndata) = _trySwap(swapRouter, key, allowedParams);
        if (!res.allowedSuccess) revert AllowedSwapFailed(allowedReturndata);

        res.modifyRouter = address(modifyRouter);
        res.swapRouter = address(swapRouter);
        res.token0 = Currency.unwrap(currency0);
        res.token1 = Currency.unwrap(currency1);
    }

    function _simulateBlockedSwap(Config memory cfg, Result memory res) internal {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(res.token0),
            currency1: Currency.wrap(res.token1),
            fee: cfg.fee,
            tickSpacing: cfg.tickSpacing,
            hooks: IHooks(cfg.hook)
        });

        IPoolManager.SwapParams memory blockedParams = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(cfg.blockedInput),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        (res.blockedSuccess, res.blockedReturndata) = _trySwap(PoolSwapTest(res.swapRouter), key, blockedParams);
        if (res.blockedSuccess) revert BlockedSwapUnexpectedlySucceeded();
    }

    function _logResult(Config memory cfg, Result memory res) internal pure {
        console2.log("Sepolia live demo completed");
        console2.log("PolicyRegistry:", cfg.policyRegistry);
        console2.log("UniswapExeGuard:", cfg.hook);
        console2.log("PoolManager:", cfg.poolManager);
        console2.log("PoolModifyLiquidityTest:", res.modifyRouter);
        console2.log("PoolSwapTest:", res.swapRouter);
        console2.log("Token0:", res.token0);
        console2.log("Token1:", res.token1);
        console2.log("Allowed swap success:", res.allowedSuccess);
        console2.log("Blocked swap success:", res.blockedSuccess);
        console2.log("Blocked revert selector:");
        console2.logBytes4(_selector(res.blockedReturndata));
    }

    function _loadConfig() internal view returns (Config memory cfg) {
        cfg.owner = vm.envOr("OWNER", address(0));
        if (cfg.owner == address(0)) revert OwnerMissing();

        cfg.poolManager = vm.envAddress("POOL_MANAGER");
        cfg.policyRegistry = vm.envAddress("POLICY_REGISTRY");
        cfg.hook = vm.envAddress("UNISWAP_EXE_GUARD");

        cfg.tokenMint = vm.envOr("LIVE_TOKEN_MINT", uint256(1_000_000 ether));
        cfg.liquidityDelta = vm.envOr("LIVE_LIQUIDITY_DELTA", uint256(1_000_000));
        cfg.allowedInput = vm.envOr("LIVE_ALLOWED_INPUT", uint256(0.1 ether));
        cfg.blockedInput = vm.envOr("LIVE_BLOCKED_INPUT", uint256(2 ether));
        cfg.maxSwapAbs = vm.envOr("LIVE_MAX_SWAP_ABS", uint256(1 ether));
        cfg.cooldownSeconds = vm.envOr("LIVE_COOLDOWN_SECONDS", uint256(0));
        cfg.fee = uint24(vm.envOr("LIVE_POOL_FEE", uint256(3000)));
        cfg.tickSpacing = int24(int256(vm.envOr("LIVE_TICK_SPACING", uint256(60))));
        cfg.tickLower = int24(vm.envOr("LIVE_TICK_LOWER", int256(-120)));
        cfg.tickUpper = int24(vm.envOr("LIVE_TICK_UPPER", int256(120)));
    }

    function _validateConfig(Config memory cfg) internal pure {
        if (cfg.tickLower >= cfg.tickUpper) revert InvalidTickRange(cfg.tickLower, cfg.tickUpper);
        if (cfg.tickSpacing <= 0 || cfg.tickLower % cfg.tickSpacing != 0 || cfg.tickUpper % cfg.tickSpacing != 0) {
            revert InvalidTickSpacing(cfg.tickSpacing, cfg.tickLower, cfg.tickUpper);
        }
    }

    function _validateOwners(Config memory cfg) internal view {
        PolicyRegistry registry = PolicyRegistry(cfg.policyRegistry);
        UniswapExeGuard hook = UniswapExeGuard(cfg.hook);
        if (registry.owner() != cfg.owner) revert RegistryOwnerMismatch(cfg.owner, registry.owner());
        if (hook.owner() != cfg.owner) revert HookOwnerMismatch(cfg.owner, hook.owner());
    }

    function _deploySortedTokens(uint256 tokenMint)
        internal
        returns (Currency currency0, Currency currency1, IERC20Minimal token0, IERC20Minimal token1)
    {
        address tokenA = address(new TestERC20(tokenMint));
        address tokenB = address(new TestERC20(tokenMint));
        return _sortCurrencies(tokenA, tokenB);
    }

    function _buildKey(Config memory cfg, Currency currency0, Currency currency1) internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: cfg.fee,
            tickSpacing: cfg.tickSpacing,
            hooks: IHooks(cfg.hook)
        });
    }

    function _initializeAndFundPool(
        Config memory cfg,
        IPoolManager manager,
        PoolKey memory key,
        IERC20Minimal token0,
        IERC20Minimal token1,
        PoolModifyLiquidityTest modifyRouter,
        PoolSwapTest swapRouter
    ) internal {
        manager.initialize(key, TickMath.getSqrtPriceAtTick(0));

        token0.approve(address(modifyRouter), type(uint256).max);
        token1.approve(address(modifyRouter), type(uint256).max);
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);

        IPoolManager.ModifyLiquidityParams memory lpParams = IPoolManager.ModifyLiquidityParams({
            tickLower: cfg.tickLower,
            tickUpper: cfg.tickUpper,
            liquidityDelta: int256(cfg.liquidityDelta),
            salt: bytes32(0)
        });
        modifyRouter.modifyLiquidity(key, lpParams, bytes(""));
    }

    function _sortCurrencies(address tokenA, address tokenB)
        internal
        pure
        returns (Currency currency0, Currency currency1, IERC20Minimal erc20_0, IERC20Minimal erc20_1)
    {
        if (tokenA < tokenB) {
            return (Currency.wrap(tokenA), Currency.wrap(tokenB), IERC20Minimal(tokenA), IERC20Minimal(tokenB));
        }
        return (Currency.wrap(tokenB), Currency.wrap(tokenA), IERC20Minimal(tokenB), IERC20Minimal(tokenA));
    }

    function _trySwap(PoolSwapTest swapRouter, PoolKey memory key, IPoolManager.SwapParams memory params)
        internal
        returns (bool success, bytes memory returndata)
    {
        PoolSwapTest.TestSettings memory settings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        bytes memory payload = abi.encodeCall(PoolSwapTest.swap, (key, params, settings, bytes("")));
        (success, returndata) = address(swapRouter).call(payload);
    }

    function _selector(bytes memory returndata) internal pure returns (bytes4 sel) {
        if (returndata.length < 4) return bytes4(0);
        assembly {
            sel := mload(add(returndata, 0x20))
        }
    }
}
