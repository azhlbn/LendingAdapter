
![Algem](https://github.com/azhlbn/LendingAdapter/blob/main/header_algem_logo.png)

## Sio2 Lending Adapter

Sio2Adapter acts as an intermediary between Algem users and the SiO2 lending protocol. When interacting with the adapter, users are able to use their nASTR tokens as collateral in SiO2 without losing the ability to earn rewards on them. They can also borrow tokens, starting with ASTR initially, and more tokens will be added in the future. The functionality of the adapter reflects the capabilities of the SiO2 lending protocol for users while acting as a regular user for SiO2.

## Architecture

The adapter consists of three contracts:

`Sio2Adapter`
The primary contract contains the logic related to deposits and loans, balance management, and liquidation.
Main functions:
- supply
- borrow
- addSTokens
- claimRewards
- liquidationCall
- repayPart
- repayFull
- withdraw

`Sio2AdapterAssetManager`
The auxiliary contract contains all the necessary logic to handle asset-related operations. This includes adding/removing tokens, monitoring internal asset balances, calculating estimate user balances, and controlling asset parameters.

`Sio2AdapterData`
The auxiliary contract enables obtaining a set of values necessary for display in the user interface, such as APR, APY, changes in debt and deposit, based on the user-inputted token amount.