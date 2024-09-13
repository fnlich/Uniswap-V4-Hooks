// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";

contract RateLimitingSwapHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;

    struct PoolRate {
        uint lastSwapTimeStamp;
        uint swapsAllowed;
        uint consumedSwaps;
    }

    mapping(PoolId => PoolRate) public PoolRates;
    uint256 NEXT_CYCLE_TIME = 1 days;
    address hook_owner;
    event Swapped(uint swap_limit_consumed);

    error SwapLimitReachedForPool(PoolId id);

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        hook_owner = msg.sender;
    }
    function setHookOwner(address new_hook_owner) external {
        require(
            hook_owner == msg.sender,
            "Only Hook Owner can change hook_owner"
        );
        hook_owner = new_hook_owner;
    }

    function setPoolRate(PoolId p_id, uint maxSwapsPerDay) external {
        require(
            hook_owner == msg.sender,
            "Only Hook Owner can change Pool rates"
        );
        PoolRates[p_id].lastSwapTimeStamp = block.timestamp;
        PoolRates[p_id].swapsAllowed = maxSwapsPerDay;
        PoolRates[p_id].consumedSwaps = 0;
    }

    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        PoolId p_id = key.toId();
        if (
            PoolRates[p_id].lastSwapTimeStamp + NEXT_CYCLE_TIME <
            block.timestamp
        ) {
            PoolRates[p_id].consumedSwaps = 0;
            PoolRates[p_id].lastSwapTimeStamp = block.timestamp;
        }
        uint consumed_swaps = PoolRates[p_id].consumedSwaps;

        if (
            consumed_swaps == PoolRates[p_id].swapsAllowed
        ) {
            revert SwapLimitReachedForPool(p_id);
        }
        PoolRates[p_id].consumedSwaps = consumed_swaps + 1;
        PoolRates[p_id].lastSwapTimeStamp = block.timestamp;
        emit Swapped(
             PoolRates[p_id].consumedSwaps
        );

        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            0
        );
    }
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: true,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }
}
