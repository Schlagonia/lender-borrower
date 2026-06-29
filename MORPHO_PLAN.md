# Morpho Strategy Plan

- Need Morpho Blue integration: new strategy inheriting `BaseLenderBorrower` that overrides supply/withdraw/borrow/repay/etc. using Morpho core calls.
- Require official interfaces (IMorpho, structures, helper libraries) from https://github.com/morpho-org/morpho-blue or docs; download once network is enabled.
- Strategy must support arbitrary marketId (passed at deployment) and rely on AuctionSwapper + UniswapV3Swapper for reward/asset swaps.
- New factory: accepts Morpho core address via constructor, deploys strategies for given asset, borrow token, lender vault, marketId. Factory maps by marketId for tracking.
- Avoid touching `BaseLenderBorrower`; only override hooks inside strategy.
- Hold any lens logic within the strategy or a local library (no external dependencies beyond repo/periphery).
- Postponed tests until user reviews implementation.

Pending tasks once interfaces are available:
1. Vendor Morpho interfaces (IMorpho, MorphoBalances, structs) into `src/interfaces/morpho/`.
2. Implement `MorphoBlueLenderBorrower.sol` leveraging those interfaces, plus Auction/Uniswap swappers for reward/liquidity handling.
3. Create `MorphoBlueLenderBorrowerFactory.sol` to deploy configured strategies keyed by `marketId`.
4. Update README/AGENTS if needed to mention Morpho support (after code is ready).
