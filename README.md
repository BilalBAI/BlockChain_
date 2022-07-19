# BlockChain_Projects
## ETHBarrierOptions
ETHBarrierOptions is smart contract based on the study of a ChainLink Vanilla Option example: [Build a DeFi Call Option Exchange With Chainlink Price Feeds](https://blog.chain.link/defi-call-option-exchange-in-solidity/)

This project implements a ETH Knock-out Barrier Call Options which gives the buyer the right, but not the obligation, to purchase ETH at a predetermined amount and strike price, if the ETH price does not go below a specified knockout level during the option's life.

### ENV
This smart contract is based on Rinkeby Test Net.  [Get Rinkeby ETH](https://rinkebyfaucet.com/)

### Functions
* getEthPrice():  get current ETH price in USD without decimals

* writeOption(): write an option with strike, premium, days_to_expiry, knockOutLevel, and tknAmt specified.   Note strike, premium, knockOutLevel are all intergers without decimals.  The writer must have enough ETH for tknAmt.

* buyOption(): buy an option by referring to the option ID.   The buyer should have enough ETH for premium and the option contract is not canceled/expired/knockedOut.

* exercise(): allow the buyer to exercise an option if it is not canceled/expired/knockedOut.

* knockOutValidation(): validate if any existing options hit knockout level.  This function needs to be called periodically (e.g. every hour) which can be achieved in two ways:
  1. Centralized: The writers have potential incentives to schedule to run this function
  2. Decentralized: The function can be registered on [Chainlink Upkeep App](https://keepers.chain.link/new-time-based) with a time-based trigger

* cancelOption():  allow the writer the cancel the option and retrieve tockens if the option is not bought

* retrieveExpiredFunds(): Allows writer to retrieve funds from an expired, non-exercised, non-canceled contract

* getTimeStampNow():  Get the current timestamp in unix format
