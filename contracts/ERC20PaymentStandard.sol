/// SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC20PaymentStandard} from './IERC20PaymentStandard.sol';

/**
* @title ERC20PaymentStandard
* @author Carson Case
* @notice This contract is a standard meant to be overriden that works with the Bonds contract to offer noncolateralized, flexable lending onchain
 */
contract ERC20PaymentStandard is ERC1155Holder{
    // Initialized in constructor
    address public bondContract;
    
    //Loan object. Stores lots of info about each loan
    struct loan {
        bool issued;
        address ERC20Address;
        address borrower;
        //bytes32 merkleRoot;
        uint256 paymentPeriod;
        uint256 paymentDueDate;
        uint256 minPayment;
        uint256 interestRateInverse;
        uint256 accrualPeriod;
        uint256 principal;
        uint256 totalPaymentsValue;
        uint256 awaitingCollection;
        uint256 paymentComplete;
    }
    
    //Two mappings. One to get the loans for a user. And the other to get the the loans based off id
    mapping(uint256 => loan) public loanLookup;
    mapping(address => uint256[]) public loanIDs;
    
    /**
    * @notice just sets bonds contract
    * @param _bonds contract
     */
    constructor(address _bonds){
        bondContract = _bonds;
    }
    
    /// @notice requires only the Bonds Contract call this function
    modifier onlyBonds{
        require(msg.sender == bondContract, "Only the bond contract can call this function");
        _;
    }
    
    /// @notice requires contract is not paid off
    modifier incomplete(uint256 _id){
        require(loanLookup[_id].paymentComplete <
        loanLookup[_id].totalPaymentsValue,
        "This contract is alreayd paid off");
        _;
    }
    
    /**
    * @notice gets the number of loans a person has
    * @param _who is who to look up
    * @return length
     */
    function getNumberOfLoans(address _who) external virtual view returns(uint256){
        return loanIDs[_who].length;
    }
    
    /**
    * @notice called when bonds are issued so as to make sure lender can only mint bonds once.
    * @param _id loan ID
    * @return the loan principal (so bonds knows how many NFTs to mint)
    * @return the borrowers address (so bonds can make sure borrower is calling this function)
     */
    function issueBonds(uint256 _id) external virtual onlyBonds returns(uint256,address){
        require(!loanLookup[_id].issued,"You have already issued bonds for this loan");
        loanLookup[_id].issued = true;
        return(loanLookup[_id].principal,loanLookup[_id].borrower);
    }
    
    /**
    * @notice Called each time new NFTs are minted by staking
    * @param _amm the ammount of interest to add
    * @param _id is the id of the loan
    * @return true if added. Will not add interest if payment has been completed.
    *This prevents lenders from refusing to end a loan when it is rightfully over by forever
    *increasing the totalPaymentsValue through interest staking and never fully collecting payment.
    *This also means that if lenders do not realize interest gains soon enough they may not be able to collect them before
    *the borrower can complete the loan.
     */
    function addInterest(uint256 _amm, uint256 _id) onlyBonds external virtual returns(bool){
        if(!isComplete(_id)){
            loanLookup[_id].totalPaymentsValue += _amm;
            return true;
        }else{
            return false;
        }
    }

    /**
    * @notice get the interest rate of a loan. Makes it easy for other contract since it doens't have to use parse struct
    * @param _id is the loan ID
    * @return inverse interest rate
     */
    function getInterest(uint256 _id) external virtual view returns(uint256){
        return(loanLookup[_id].interestRateInverse);
    }
    
    /**
    * @notice This contract is not very forgiving. Miss one payment and you're marked as delinquent. Unless contract is complete
    * @param _id is the hash id of the loan. Same as bond ERC1155 ID as well
    * @return if delinquent or not. Meaning missed a payment
     */
    function isDelinquent(uint256 _id) public virtual view returns(bool){
        return (block.timestamp >= loanLookup[_id].paymentDueDate && !isComplete(_id));
    }
    
     /**
    * @notice contract must be configured before bonds are issued. Pushes new loan to array for user
    * @dev borrower is msg.sender for testing. In production might want to make this a param
    * @param _erc20 is the ERC20 contract address that will be used for payments
    * @param _borrower is the borrower loan is being configured for. Keep in mind. ONLY this borrower can mint bonds to start the loan
    * @param _minPayment is the minimum payment that must be made before the payment period ends
    * @param _paymentPeriod payment must be made by this time or delinquent function will return true
    * @param _principal the origional loan value before interest
    * @param _inverseInterestRate the interest rate expressed as inverse. 2% = 1/5 = inverse of 5
    * @param _accrualPeriod the time it takes for interest to accrue in seconds
     */
    function configureNew(
    address _erc20,
    address _borrower,
    uint256 _minPayment, 
    uint256 _paymentPeriod, 
    uint256 _principal, 
    uint256 _inverseInterestRate, 
    uint256 _accrualPeriod
    )
    external
    virtual
    returns(uint256)
    {
        //Create new ID for the loan
        uint256 id = getId(_borrower, loanIDs[_borrower].length);
        //Push to loan IDs
        loanIDs[_borrower].push(id);
        //Add loan info to lookup
        loanLookup[id] = loan(
        {
            issued: false,
            ERC20Address: _erc20,
            borrower: msg.sender,
            paymentPeriod: _paymentPeriod,
            paymentDueDate: block.timestamp + _paymentPeriod,
            minPayment: _minPayment,
            interestRateInverse: _inverseInterestRate,
            accrualPeriod: _accrualPeriod,
            principal: _principal,
            totalPaymentsValue: _principal,               //For now. Will update with interest updates
            awaitingCollection: 0,
            paymentComplete: 0
            }
        );
        return id;
    }
    
    /**
    * @notice function handles the payment of the loan. Does not have to be borrower
    *as payment comes in. The contract holds it until collection by bond owners. MUST APPROVE FIRST in ERC20 contract first
    * @param _id to pay off
    * @param _erc20Ammount is ammount in loan's ERC20 to pay
     */
    function payment(uint256 _id, uint256 _erc20Ammount) 
    external 
    virtual
    incomplete(_id)
    {
        loan memory ln = loanLookup[_id];
        require(_erc20Ammount >= ln.minPayment ||                                   //Payment must be more than min payment
                ln.totalPaymentsValue - ln.paymentComplete < ln.minPayment,     //Exception for the last payment (remainder)
                "You must make the minimum payment");
                
        IERC20(ln.ERC20Address).transferFrom(msg.sender, address(this), _erc20Ammount);     
        loanLookup[_id].awaitingCollection += _erc20Ammount;                         
        loanLookup[_id].paymentDueDate = block.timestamp + ln.paymentPeriod;             //Reset paymentTimer;
        loanLookup[_id].paymentComplete += _erc20Ammount;                                //Increase paymentComplete
    }
    
    /*
     * handles payment collection automatically when ERC1155s are sent. Function overriden from OpenZeppelin ERC1155Holder.sol
     */
    function onERC1155Received(address _operator, address _from, uint256 _id, uint256 _value, bytes calldata _data) public virtual override returns(bytes4){
        require(loanLookup[_id].issued, "this loan has not been issued yet. How do you even have bonds for it???");
        require(_value <= loanLookup[_id].awaitingCollection,"There is not enough payments available for collection");
        IERC20 erc20 = IERC20(loanLookup[_id].ERC20Address);
        erc20.transfer(_from, _value);
        return this.onERC1155Received.selector;
    }
    
    /**
    * @notice helper function
    * @param _id of loan to check
    * @return return if the contract is payed off or not as bool
     */
    function isComplete(uint256 _id) public virtual view returns(bool){
        return loanLookup[_id].paymentComplete >=
        loanLookup[_id].totalPaymentsValue ||
        !loanLookup[_id].issued;
    }

    /**
    * @notice Returns the ID for a loan given the borrower and index in the array
    * @param _borrower is borrower
    * @param _index is the index in the borrowers loan array
    * @return the loan ID
     */
    //
    function getId(address _borrower, uint256 _index) public virtual view returns(uint256){
        uint256 id = uint256(
            keccak256(abi.encodePacked(
            address(this),
            _borrower,
            _index
        )));
        return id;
    }
}