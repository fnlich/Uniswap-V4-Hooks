
# Build Uniswap V4 Hooks

This repository is dedicated to explorer , build and share my in-depth learnings and insights about Uniswap V4 Codebase.

## Articles
- [Build a Rate Limiting Hook to put limit on max swaps allowed per pool per some time period ](./RateLimitingSwapHook.md)
- [Build your First Fully on-chain Uniswap V4 hook line-by-line with assembly level explanation ( From a Security Researcher Perspective )](./Build-Your-Hook.md)

## Built Hooks
### 2. [Rate Limiting Swaps Hook](./src/RateLimitingSwapHook.sol)
This is a creative hook that allows the creator to put limit on number of swaps allowed per pool for a certain amount of time ( i.e one day , one month etc. ) . It leverages the power of following hooks

- beforeSwap
- beforeSwapReturnDelta


### 1. [Simple Initialize Pool Hooks](./src/InitializeHook.sol)
This Hook contract is a simple one dedicated to check if certain hook callback is called.
The hooks implemented are 

- beforeInitialize Hook
- afterInitialize Hook

##### Powered By v4-template

