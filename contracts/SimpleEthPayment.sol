/// SPDX-License-Identifier: None
pragma solidity ^0.8.0;

//For Remix:
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC1155/ERC1155.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC1155/utils/ERC1155Holder.sol";
//For Local:
//import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
//import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

/**
* @title SimpleEthPayment
* @author Carson Case
*
* @notice the payment contract for demo
* @dev ideas for improvement
*   - big one. Make this more versitile. Multiple users/loans
*   - make another for ERC-20s
*   - add collaterall as a feature
*   - change inverse interest rate to inverse interest*10^P. P being precision. This could add more precision to rate
*   - if a lender refuses to unstake a bond he could revive a dead loan or keep it alive forever
*       * to prevent this make the totalPaymentsValue hardcoded and calculated instead of updated
*       * or have a max it can't surpass. 
 */
contract SimpleEthPayment is ERC1155Holder{
    
    //State Variables
    address public bondContract;
    address public borrower;
    //bytes32 merkleRoot;
    uint256 public paymentPeriod;
    uint256 public paymentDueDate;
    uint256 public minPayment;
    uint256 public interestRateInverse;
    uint256 public accrualPeriod;
    uint256 public principal;
    uint256 public totalPaymentsValue;
    uint256 public awaitingCollection;
    uint256 public paymentComplete;
    
    /**
    * @notice this contract must be deployed after the bond contract. As it is a parameter
    * @dev borrower is msg.sender for testing. In production might want to make this a param
    * @param _bondContract is the bond contract address
    * @param _minPayment is the minimum payment that must be made before the payment period ends
    * @param _paymentPeriod payment must be made by this time or delinquent function will return true
    * @param _principal the origional loan value before interest
    * @param _inverseInterestRate the interest rate expressed as inverse. 2% = 1/5 = inverse of 5
    * @param _accrualPeriod the time it takes for interest to accrue in seconds
     */
    constructor(address _bondContract, uint256 _minPayment, uint256 _paymentPeriod, uint256 _principal, uint256 _inverseInterestRate, uint256 _accrualPeriod){
        borrower = msg.sender;
        bondContract = _bondContract;
        minPayment = _minPayment;
        paymentPeriod = _paymentPeriod;
        principal = _principal;
        totalPaymentsValue = principal;               //For now. Will update with interest updates
        interestRateInverse = _inverseInterestRate;               
        paymentDueDate = block.timestamp + _paymentPeriod;
        accrualPeriod = _accrualPeriod;
    }
    
    /// @notice requires contract is not paid off
    modifier incomplete{
        require(paymentComplete < totalPaymentsValue, "This contract is alreayd paid off");
        _;
    }
    
    /// @notice requires only the Bonds Contract call this function
    modifier onlyBonds{
        require(msg.sender == bondContract, "Only the bond contract can call this function");
        _;
    }
    
    /**
    * @notice function handles the payment of the loan. Does not have to be borrower
    *as payment comes in. The contract holds it until collection by bond owners. 
     */
    function payment() payable external incomplete{
        require(msg.value >= minPayment ||                              //Payment must be more than min payment
                totalPaymentsValue - paymentComplete < minPayment,      //Exception for the last payment (remainder)
                "You must make the minimum payment");
                
        awaitingCollection += msg.value;                         
        paymentDueDate = block.timestamp + paymentPeriod;           //Reset paymentTimer;
        paymentComplete += msg.value;                               //Increase paymentComplete
    }
    
    /**
    * @notice collect the eth in contract made as payments. Must trade in ERC-1155 bonds
    *Must approve the transfer in Bonds contract first
    * @param _amm is the ammount to collect (and trade in)
     */
    function collect(uint256 _amm) external{
        require(awaitingCollection <= _amm, "There is not enough payments ready for collection yet. You must wait until the borrower makes the next payment");
        ERC1155 nft = ERC1155(bondContract);
        uint256 id = uint256(uint160(address(this)));
        require(nft.balanceOf(msg.sender, id) >= _amm, "You do not have the bond balance required to make this collection");
        nft.safeTransferFrom(msg.sender, address(this), id, _amm, "");
        awaitingCollection -= _amm;
        payable(msg.sender).transfer(_amm);
    }
    
    /**
    * @notice This contract is not very forgiving. Miss one payment and you're marked as delinquent
    * @return if delinquent or not. Meaning missed a payment
     */
    function isDelinquent() external view incomplete returns(bool){
        return block.timestamp >= paymentDueDate;
    }
    
    /**
    * @notice Called each time new NFTs are minted by staking
    * @param _amm the ammount of interest to add
     */
    function addInterest(uint256 _amm) onlyBonds external{
        totalPaymentsValue += _amm;
    }

    /**
    * @notice helper function. External because it's used in an interface
    * @return return if the contract is payed off or not as bool
     */
    function isComplete() external view returns(bool){
        return paymentComplete >= totalPaymentsValue;
    }


}

