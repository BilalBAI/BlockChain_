// Reference: https://github.com/gmondok/ChainlinkCallOptions/blob/main/chainlinkOptions.sol
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol";

//Test Net: Rinkeby https://rinkebyfaucet.com/

contract ETHBarrierOptions {
    //ETH Knock-out Barrier Call Options, the option contract ceases to exist if hit knockOutLevel
    //Overflow safe operators
    using SafeMath for uint256;
    //Pricefeed interfaces
    AggregatorV3Interface internal ethFeed;

    uint256 ethPrice;
    //Precomputing hash of strings
    address payable contractAddr;

    //Options stored in arrays of structs
    struct option {
        uint256 strike; //Price in USD (0 decimal places) option allows buyer to purchase tokens at
        uint256 premium; //Fee in contract token that option writer charges
        uint256 expiry; //Unix timestamp of expiration time
        uint256 knockOutLevel; // Knock Out Barrier > strike price
        uint256 amount; //Amount of tokens the option contract is for
        bool exercised; //Has option been exercised
        bool canceled; //Has option been canceled
        bool knockedOut; //Has option been knocked out
        uint256 id; //Unique ID of option, also array index
        uint256 latestCost; //Helper to show last updated cost to exercise
        address payable writer; //Issuer of option
        address payable buyer; //Buyer of option
    }
    option[] public ethOpts;

    //Rinkeby feeds: https://docs.chain.link/docs/reference-contracts
    constructor() public {
        //ETH/USD Rinkeby feed
        ethFeed = AggregatorV3Interface(
        0x8A753747A1Fa494EC906cE90E9f37563A8AF630e
    );
    }

    //Returns the latest ETH price
    function getEthPrice() public view returns (uint256) {
        (
            uint80 roundID,
            int256 price,
            uint256 startedAt,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = ethFeed.latestRoundData();
        // If the round is not complete yet, timestamp is 0
        require(timeStamp > 0, "Round not complete");
        //Price should never be negative thus cast int to unit is ok
        //Remove the decimal part (Price is 8 decimal places)
        return uint256(price).div(10**8);
    }

    //Returns the latest ETH price
    function getTimeStampNow() public view returns (uint256) {
        return block.timestamp;
    }

    //Updates prices to latest
    function updatePrices() internal {
        ethPrice = getEthPrice();
    }

    // This function needs to be registered on Chainlink Upkeep so that knvock 
    // https://keepers.chain.link/new-time-based
    // https://docs.chain.link/docs/chainlink-keepers/introduction/
    function knockOutValidation() public {
        updatePrices();
        uint arrayLength = ethOpts.length;
        for (uint i=0; i<arrayLength; i++) {
            if (!ethOpts[i].exercised && !ethOpts[i].knockedOut && !ethOpts[i].canceled && ethPrice<ethOpts[i].knockOutLevel) {
                ethOpts[i].knockedOut = true;
            } else {
                continue;
            }
        }
    }

    //Allows user to write a call option
    //Takes which token, a strike price(USD per token w/0 decimal places), premium(same unit as token), expiration time(unix) and how many tokens the contract is for
    function writeOption(
        uint256 strike,
        uint256 premium,
        uint256 days_to_expiry,
        uint256 knockOutLevel,
        uint256 tknAmt
    ) public payable {
        updatePrices();
        require(msg.value == tknAmt, "Incorrect amount of ETH supplied");
        require( knockOutLevel < ethPrice, "knockOutLevel must below spot price");
        uint256 latestCost = strike.mul(tknAmt).div(ethPrice); //current cost to exercise in ETH
        uint256 expiry=block.timestamp+days_to_expiry*24*60*60;
        ethOpts.push(
            option(
                strike,
                premium,
                expiry,
                knockOutLevel,
                tknAmt,
                false,
                false,
                false,
                ethOpts.length,
                latestCost,
                payable(msg.sender),
                payable(address(0))
            )
        );
    }

    //Purchase a call option, needs ID of option and payment
    function buyOption(uint256 ID) public payable {
        updatePrices();
        require(
            !ethOpts[ID].canceled && !ethOpts[ID].knockedOut && ethOpts[ID].expiry > block.timestamp,
            "Option is canceled/expired/knockedOut and cannot be bought"
        );
        //Transfer premium payment from buyer
        require(
            msg.value == ethOpts[ID].premium,
            "Incorrect amount of ETH sent for premium"
        );
        //Transfer premium payment to writer
        ethOpts[ID].writer.transfer(ethOpts[ID].premium);
        ethOpts[ID].buyer = payable(msg.sender);
    }

    //Exercise the call option, needs ID of option and payment
    function exercise(uint256 ID) public payable {
        //If not expired and not already exercised, allow option owner to exercise
        //To exercise, the strike value*amount equivalent paid to writer (from buyer) and amount of tokens in the contract paid to buyer
        require(
            ethOpts[ID].buyer == msg.sender,
            "You do not own this option"
        );
        require(
            !ethOpts[ID].exercised,
            "Option has already been exercised"
        );
        require(
            !ethOpts[ID].knockedOut,
            "Option has already been knocked out"
        );
        require(ethOpts[ID].expiry > block.timestamp, "Option is expired");
        //Conditions are met, proceed to payouts
        updatePrices();
        //Cost to exercise
        uint256 exerciseVal = ethOpts[ID].strike * ethOpts[ID].amount;
        //Equivalent ETH value using Chainlink feed
        uint256 equivEth = exerciseVal.div(ethPrice); 
        //Buyer exercises option by paying strike*amount equivalent ETH value
        require(
            msg.value == equivEth,
            "Incorrect ETH amount sent to exercise"
        );
        //Pay writer the exercise cost
        ethOpts[ID].writer.transfer(equivEth);
        //Pay buyer contract amount of ETH
        payable(msg.sender).transfer(ethOpts[ID].amount);
        ethOpts[ID].exercised = true;
    }

    //Allows option writer to cancel and get their funds back from an unpurchased option
    function cancelOption(uint ID) public payable {
        require(msg.sender == ethOpts[ID].writer, "You did not write this option");
        //Must not have already been canceled or bought
        require(!ethOpts[ID].canceled && ethOpts[ID].buyer == address(0), "This option cannot be canceled");
        ethOpts[ID].writer.transfer(ethOpts[ID].amount);
        ethOpts[ID].canceled = true;
    }

    //Allows writer to retrieve funds from an expired, non-exercised, non-canceled contract
    function retrieveExpiredFunds(uint256 ID)
        public
        payable
    {
        require(
            msg.sender == ethOpts[ID].writer,
            "You did not write this option"
        );
        //Must be expired, not exercised and not canceled
        require(
            ethOpts[ID].expiry <= block.timestamp &&
                !ethOpts[ID].exercised &&
                !ethOpts[ID].canceled,
            "This option is not eligible for withdraw"
        );
        ethOpts[ID].writer.transfer(ethOpts[ID].amount);
        //Repurposing canceled flag to prevent more than one withdraw
        ethOpts[ID].canceled = true;
    }

    //This is a helper function to help the user see what the cost to exercise an option is currently before they do so
    //Updates lastestCost member of option which is publicly viewable
    function updateExerciseCost(uint256 ID) public {
        updatePrices();
        ethOpts[ID].latestCost = ethOpts[ID]
            .strike
            .mul(ethOpts[ID].amount)
            .div(ethPrice);
    }
}


