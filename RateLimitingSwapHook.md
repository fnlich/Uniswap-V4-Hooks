# Rate Limiting Swap Hook for Uniswap V4
<div align="center">
<img src="https://ih1.redbubble.net/image.4879086683.3987/carp,x_large,product,750x1000.u3.webp" alt="Uni V4" width="400" height="400">
</div>

## Introduction
Hey there ,it's good to meet you.
Thank you for coming here to learn how you can build your very own Hook that can limit the number of swaps per pool.This article aims to explain the functionality and implementation details of the `RateLimitingSwapHook.sol` contract for Uniswap V4. 

## Pre-Requisite
If this is your first time building hooks on Uniswap V4 , its going to be a bit difficult due to new semantics introduced in V4.

I would highly suggest you to read & and understand my first-most article on [Build Your first Hook](https://github.com/0xumarkhatab/Uniswap-V4-Hooks/blob/main/Build-Your-Hook.md) and then come back to this article to build this cool hook.

### Functionality Overview

If you've gone through the `Build Your first Hook` article , you might be aware that uniswap V4 has several hooks like 

`beforeSwap`
`afterSwap` 
etc.

When a swap is initiated , `beforeSwap` function of the provided hook is called to execute custom logic before the swap happens i.e preparing some conditions for swap.

At a high level , the `RateLimitingSwapHook` is designed to 

- Continue swap is rate limit of pool is not reached for the current cycle ( it's currently a day )
- Stop the swap otherwise

It maintains a mapping (`PoolRates`) that stores the following information for each pool:

* `lastSwapTimeStamp`: The timestamp of the last swap for this pool.
* `swapsAllowed`: The maximum number of swaps allowed within a specific timeframe (e.g., per day). This is controlled by the `hook_owner` that can increase or decrease the max swaps allowed for a certain pool.
* `consumedSwaps`: The number of swaps performed for this pool since the `lastSwapTimeStamp`.

Before each swap, the hook checks if the `consumedSwaps` have reached the `swapsAllowed` limit for the given pool. 

* If the limit is not reached, the swap proceeds normally, and the `consumedSwaps` counter is incremented.
* If the limit is reached, the swap is reverted with a custom error message (`SwapLimitReachedForPool`).

**Benefits:**

* Prevents excessive swapping activity for a specific pool, potentially stabilizing prices or mitigating flash loan attacks.
* Offers granular control over swap rates for individual pools.

### Implementation Details


#### 1. Contract Structure

The `RateLimitingSwapHook` contract inherits from the base `BaseHook` provided by the Uniswap V4 periphery library. It defines the following key elements:

* `PoolRate` struct: Stores information about swap rates for each pool.
* `PoolRates` mapping: Maps pool IDs to their corresponding `PoolRate` struct.
* `CYCLE_TIME`: Constant defining the duration of the swap rate cycle (e.g., 1 day).
* `hook_owner`: Address of the account authorized to manage the hook configuration.
* `Swapped` event: Emitted after each successful swap, including the current number of consumed swaps.

#### 2. Functions

* `constructor`: Initializes the hook with a reference to the pool manager.
* `setHookOwner`: Allows the hook owner to change the ownership of the hook.
* `setPoolRate`: Sets the maximum number of allowed swaps and resets the swap counter for a specific pool ID. This function can only be called by the hook owner.
* `beforeSwap`: This function is called before each swap. It checks the swap rate limit for the pool and either allows the swap or reverts it based on the remaining swaps.
* `getHookPermissions`: Returns the permissions associated with this hook. In this case, it indicates that the hook intercepts the `beforeSwap` call.


Here's the Hook that performs the above mentioned task of getting Complete control of how many swaps per day ,week or month are allowed for a certain Pool.

```solidity
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
    uint256 CYCLE_TIME = 1 days; // put any time period here
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
        // Get pool ID to represent all the information contained inside the pool
        PoolId p_id = key.toId();

        // If More time than the intended cycle has passed ( i.e if Cycle time is 1 day , and swap has happened more than one day ago)  then its time to update the swap variables
        // Where total consumed will become 0 

        if (
            PoolRates[p_id].lastSwapTimeStamp + CYCLE_TIME <
            block.timestamp
        ) {
            PoolRates[p_id].consumedSwaps = 0;
            PoolRates[p_id].lastSwapTimeStamp = block.timestamp;
        }
        uint consumed_swaps = PoolRates[p_id].consumedSwaps;

        // revert if rate limit has been passed for this pool.
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
        // Our Hook allows only two options which are
        // 1. beforeSwap 
        // 2. beforeSwapReturnDelta
        // So these are marked as true and others as false
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

```



### Testing with Foundry

I've written a test suite (`RateLimitingSwapHook.t.sol`) that verifies the functionality of the hook using `Foundry`. It will also give you a sense on how to use hooks in general .

This time we are using `SwapRouter` that performs all the needed checks on our behalf.

It performs the following steps:

Note : Step 1-4 are same as the `Build Your First Hook` article.

1. Deploys all necessary contracts, including the pool manager, hook, and swap router.
2. Defines a pool with a specific token pair.
3. Sets the desired swap rate limit for the pool using the `setPoolRate` function.
4. Initializes the pool.
5. Simulates multiple swaps (within the allowed limit) and verifies successful execution.
6. Attempts another swap after reaching the limit and expects a revert.

The code is well commented more than this article itself 

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PositionConfig} from "v4-periphery/src/libraries/PositionConfig.sol";
import {ProtocolFeeControllerTest} from "v4-core/src/test/ProtocolFeeControllerTest.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
//
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "../src/RateLimitingSwapHook.sol";
import "forge-std/Vm.sol";

contract RateLimitingSwapHookTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    PoolId poolId;
    PositionConfig config;

    function setUp() public {}
    function test_RateLimitedSwap() external {
        // Declaration of Conracts we need on the way

        // Pool manager is our main contact for initialization of pools
        IPoolManager manager_;
        // Initialize Hook is Our Custom hook that contains the different logic based on the callback
        // In our example , this custom hook implements BeforeInitalize and AfterInitalize Hooks
        // And currently it just increments a global mapping so that it becomes evident that some custom logic is executed
        // and any additional logic can be added
        RateLimitingSwapHook rateLimitingSwapHook;
        // remember in the previous part of the tutorial , we discussed how uniswap controls the protocol fees
        // using a protocolFeeController inside Pool Manager.
        // Here we are declaring that protocol fee controller
        ProtocolFeeControllerTest feeController_;

        // Deploy All the required contracts

        // Initalize the Pool Manager with initial 500k Gas for controller to suffice for making queries to protocol fees controller for protocol fees
        manager_ = new PoolManager(500000);
        feeController_ = new ProtocolFeeControllerTest();
        // Set protocol fee controller
        manager_.setProtocolFeeController(feeController);

        // Now we need to deploy 2 currencies , we will name them as USDC and AAVE
        //  Note : We are not considering the changed behaviours in them and just think of them as standard ERC20 tokens
        MockERC20 USDC = new MockERC20("USDC", "USDC", 18);
        MockERC20 AAVE = new MockERC20("AAVE", "AAVE", 18);

        // But we don't have any tokens yet . that's why we will mint some .
        // For initalize Hook , we can skip this but this will be used later when we want to add liquidity ,
        // then we will need tokens
        uint totalSupply = 10e20 ether; // time to get rich
        USDC.mint(address(this), totalSupply);
        AAVE.mint(address(this), totalSupply);

        // Time to sort tokens numerically
        // Additionally we are using a wrapper Currency on type address which does not do anything fancy
        // But provides some helper function like equals,greaterThan,lessThan instead of specifying the operators
        // Additionally it also supports the native methods like transfer
        // You can see different functions defined in v4-core/types/Currency.sol for more depth
        Currency token0;
        Currency token1;

        // Currency has a wrap fuction that takes an address as argument and returns a Currency type variable
        // that is composed of that given address
        if (USDC > AAVE) {
            token0 = Currency.wrap(address(AAVE));
            token1 = Currency.wrap(address(USDC));
        } else {
            token0 = Currency.wrap(address(USDC));
            token1 = Currency.wrap(address(AAVE));
        }

        // Deploy the hook to an address with the correct flags

        // Since Our RateLimitingSwapHook is based on only two Hooks , beforeSwap and beforeSwapReturnDelta
        // We will make our hook with those corresponding hook type flags.
        // Where | can be considered as the concatenation opeator ( Actually a bit-wise OR )
        //  Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG means our hook contains both hook flags

        // Now , we need to convert it into address that will be used to detect which hooks are supported

        //  Remeber , a hook address is determined by the hook flags it is designed for
        // Through the concatenation of those hook flags , we generate the hook address
        // Now whenever the verification is needed ,the hook address itself can be used to check if it is composed of correct flags.
        
        // TO understand deeper `BEFORE_INITIALIZE` hook , recall from our first-most article https://github.com/0xumarkhatab/Uniswap-V4-Hooks/blob/main/Build-Your-Hook.md

        // Remember Our discussion about Hooks ,  inside hooks.sol
        //  uint160 internal constant BEFORE_INITIALIZE_FLAG = 1 << 13;
        //  uint160 internal constant AFTER_ADD_LIQUIDITY_FLAG = 1 << 10;
        // etc.
        // 1<<13 in its binary represenation is 10 0000 0000 0000 ,
        // 1 << 10 in its binary represenation is 100 0000 0000
        /// For example, a hooks contract deployed to address: 0x0000000000000000000000000000000000002400
        /// has the RIGHTMOST bits '10 0100 0000 0000' which would cause the 'before initialize' and 'after add liquidity' hooks to be used.

        // Same will be applied to our two new flags

        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            )
        );
        bytes memory constructorArgs = abi.encode(manager_); //Add all the necessary constructor arguments from the hook
        deployCodeTo(
            "RateLimitingSwapHook.sol:RateLimitingSwapHook",
            constructorArgs,
            flags
        );
        rateLimitingSwapHook = RateLimitingSwapHook(flags);

        // Create the pool
        key = PoolKey(token0, token1, 3000, 60, IHooks(rateLimitingSwapHook));
        poolId = key.toId();

        /////////////////////////////////
        //// Set rate Limit for Pool ////
        ////////////////////////////////
        rateLimitingSwapHook.setPoolRate(poolId, 2);
        ///////////////////////////////

        manager_.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);

        // Provide full-range liquidity to the pool
        config = PositionConfig({
            poolKey: key,
            tickLower: TickMath.minUsableTick(key.tickSpacing),
            tickUpper: TickMath.maxUsableTick(key.tickSpacing)
        });

        //////////////////////////////
        ////// END of Intialization ///
        ///////////////////////////////

        //////////////////////////////
        //// Providing liqduity //////
        //////////////////////////////

        // Because POSM uses permit2, we must execute 2 permits/approvals.
        // 1. First, the caller must approve permit2 on the token.
        // 2. Then, the caller must approve POSM as a spender of permit2.

        IPositionManager posm_;
        IAllowanceTransfer permit2_;
        permit2_ = IAllowanceTransfer(deployPermit2());
        posm_ = IPositionManager(new PositionManager(manager_, permit2_));

        IERC20(Currency.unwrap(token0)).approve(
            address(permit2_),
            type(uint256).max
        );
        permit2_.approve(
            Currency.unwrap(token0),
            address(posm_),
            type(uint160).max,
            type(uint48).max
        );
        IERC20(Currency.unwrap(token1)).approve(
            address(permit2_),
            type(uint256).max
        );
        permit2_.approve(
            Currency.unwrap(token1),
            address(posm_),
            type(uint160).max,
            type(uint48).max
        );

        /// mint is defined in easyposm.sol
        (uint tokenId, ) = posm_.mint(
            config,
            10_000e18,
            MAX_SLIPPAGE_ADD_LIQUIDITY,
            MAX_SLIPPAGE_ADD_LIQUIDITY,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );

        //////////////////////////
        //// Liquidity Provided //
        /////////////////////////

        ////////////////////
        /// Swap ///////////
        ////////////////////


        PoolSwapTest swapRouter = new PoolSwapTest(manager_);
        // slippage tolerance to allow for unlimited price impact
        uint160 MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
        uint160 MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

        // approve tokens to the swap router
        IERC20(Currency.unwrap(token0)).approve(
            address(swapRouter),
            type(uint256).max
        );
        IERC20(Currency.unwrap(token1)).approve(
            address(swapRouter),
            type(uint256).max
        );
        
        // ---------------------------- //
        // Swap exactly 1e18 of token0 into token1
        // ---------------------------- //
        
        (
            uint lastSwapTimeStamp,
            uint SwapsAllowed,
            uint consumedSwaps
        ) = rateLimitingSwapHook.PoolRates(poolId);

        //// Setting up swap params 
        // Negative amount means we want to take in the amount from pool to our pocket
        int amountSpecified = -1e18;
        //  Sell token0 for token1 , USDC for AAVE
        bool zeroForOne = true;
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT // unlimited impact
        });

        // in v4, users have the option to receieve native ERC20s or wrapped ERC1155 tokens
        // here, we'll take the ERC20s
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest
            .TestSettings({takeClaims: true, settleUsingBurn: false});

        bytes memory hookData = new bytes(0); // no hook data for now

        // Perform all the swap and consume the rate 
        for (uint256 index = 1; index <= SwapsAllowed; index++) {
            // advance one block and perform the swap
            vm.roll(block.number + 1);
            swapRouter.swap(key, params, testSettings, hookData);
        }
        
        // Make another swap that MUST Fail
        vm.roll(block.number + 1);
        vm.expectRevert();
        swapRouter.swap(key, params, testSettings, hookData);
        
    }
}

```


And that's it , to run this Hook , do following 

1. Clone `V4-template` repo using `git clone https://github.com/uniswapfoundation/v4-template`
2. Run `forge build` to install all the dependencies
3. Create a file in `src/` named `RateLimitingSwapHook.sol` and put in the given hook implementation code in it.
4. Create a file in `test/` named `RateLimitingSwapHook.t.sol` and put in the given hook test code in it.
5. Run using `forge test --mt test_RateLimitedSwap -vvvvvv --via-ir`
6. Check the terminal output , it will look something like this at the end.

```bash


```

## And That's a Wrap
At brief , the `RateLimitingSwapHook` shows the potential of custom hooks in Uniswap V4 for modifying swap behavior and implementing custom logic within the protocol. It's exciting how many beautiful cases can be built on such a new paradigm introduced by Uniswap V4.

## At the Very end

That's it guys . 

I really appreciate you coming uptil here.

And here's my koala thanking you for putting in that work man .

Peace And i'll see you in the next one!


<div align="center">
<img src="https://ih1.redbubble.net/image.4879086683.3987/carp,x_large,product,750x1000.u3.webp" alt="Uni V4" width="400" height="400">
</div>
