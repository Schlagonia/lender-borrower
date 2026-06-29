# Repository Guidelines

## Project Structure & Module Organization
Solidity sources live in `src/`, with `LenderBorrower.sol` extending `BaseLenderBorrower.sol`, factory logic in `StrategyFactory.sol`, helpers inside `periphery/`, and shared ABIs under `src/interfaces/`. Foundry tests and fixtures use `src/test/` and `src/test/utils/`. External dependencies (`forge-std`, `openzeppelin-contracts`, `tokenized-strategy`, etc.) are vendored in `lib/`. Tooling relies on `foundry.toml`, `foundry.lock`, `.env`, and the project `Makefile`.

## Build, Test, and Development Commands
- `make build` / `forge build` – compile contracts using the Foundry config.
- `make test`, `make trace`, `make gas` – execute the Forge suite on the fork set by `ETH_RPC_URL`, toggling verbosity or gas reports.
- `make test-contract contract=StrategyOperationsTest` – narrow runs to one test contract; use `test-test` targets for method names.
- `make coverage`, `make coverage-html` – generate LCOV metrics and optional HTML in `coverage-report/`.
- `npm run lint`, `npm run format`, `npm run format:check` – apply Solhint and Prettier (`prettier-plugin-solidity`) before committing.

## Coding Style & Naming Conventions
Adopt the Prettier/Solhint defaults (4-space indentation, SPDX headers, `pragma solidity ^0.8.0`). Contracts and libraries follow PascalCase, functions and state variables use mixedCase, immutable or constant values use ALL_CAPS, and events start with PastTense verbs. Keep modifiers minimal, prefer descriptive `error` types over string-heavy `require`, and place periphery utilities in dedicated libraries instead of bloating `LenderBorrower.sol`.

## Testing Guidelines
Write `.t.sol` suites inside `src/test/`, suffixing classes with `*Test` so Make targets detect them. Run `forge test -vv --fork-url $ETH_RPC_URL` locally; switch `.env` to another RPC (e.g., `BASE_RPC_URL`) when validating multi-chain behavior. Capture traces (`make trace`) for tricky lending/borrowing flows, share targeted reproductions via `make test-contract`, and guard regressions with `make coverage` before requesting review.

## Commit & Pull Request Guidelines
Recent history uses Conventional Commits (`feat:`, `fix:`, `build:`), so keep subject lines imperative and under 72 characters. Each PR should describe motivation, summarize user-impact, list exact commands executed (tests, gas, coverage), and link to relevant issues, Yearn forum threads, or specs. Rebase frequently, call out migrations or config updates, and attach calldata or screenshots whenever behavior cannot be inferred from tests.

## Security & Configuration Tips
Duplicate `.env.example` to `.env`, set `ETH_RPC_URL` (plus optional `CHAIN_RPC_URL` and `GH_TOKEN` for CI coverage comments), and avoid committing secrets. Use Foundry broadcasting flags or hardware wallets for deployments—never inline private keys. After bumping dependencies via `forge update`, rerun `make build`, `make test`, and the Slither GitHub Action locally if possible to catch ABI or storage-layout deviations.
