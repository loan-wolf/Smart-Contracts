/// SPDX-License-Identifier: None
pragma solidity ^0.6.6;

/**
* @title IERC20PaymentStandard
* @author Carson Case
 */
interface IERC20PaymentStandard{
    // Initialized in constructor
    function bondContract() external returns(address);
    //Loan object. Stores lots of info about each loan
    struct loan {
        bool issued;
        address ERC20Address;
        address borrower;
        bytes32 chainlinkRequestId;
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
    //function loanLookup(uint256) external returns(loan memory);
    function loanIDs(address) external returns(uint256[] memory);
    function merkleRoots() external returns(bytes32);
    
    /*
    * @notice gets the number of loans a person has
    * @param _who is who to look up
    * @return length
     */
    function getNumberOfLoans(address) external view returns(uint256);
    

    function issueBonds(uint256) external returns(uint256,address);
    
    /*
    * @notice Called each time new NFTs are minted by staking
    * @param _amm the ammount of interest to add
    * @param _id is the id of the loan
    * @return true if added. Will not add interest if payment has been completed.
    *This prevents lenders from refusing to end a loan when it is rightfully over by forever
    *increasing the totalPaymentsValue through interest staking and never fully collecting payment.
    *This also means that if lenders do not realize interest gains soon enough they may not be able to collect them before
    *the borrower can complete the loan.
     */
    function addInterest(uint256, uint256) external returns(bool);

    /*
    * @notice get the interest rate of a loan. Makes it easy for other contract since it doens't have to parse struct
    * @param _id is the loan ID
    * @return inverse interest rate
     */
    function getInterest(uint256) external view returns(uint256);
    
    /*
    * @notice This contract is not very forgiving. Miss one payment and you're marked as delinquent. Unless contract is complete
    * @param _id is the hash id of the loan. Same as bond ERC1155 ID as well
    * @return if delinquent or not. Meaning missed a payment
     */
    function isDelinquent(uint256) external virtual view returns(bool);
    
     /*
    * @notice contract must be configured before bonds are issued. Pushes new loan to array for user
    * @dev borrower is msg.sender for testing. In production might want to make this a param
    * @param _erc20 is the ERC20 contract address that will be used for payments
    * @param _borrower is the borrower loan is being configured for. Keep in mind. ONLY this borrower can mint bonds to start the loan
    * @param _minPayment is the minimum payment that must be made before the payment period ends
    * @param _paymentPeriod payment must be made by this time or delinquent function will return true
    * @param _principal the origional loan value before interest
    * @param _inverseInterestRate the interest rate expressed as inverse. 2% = 1/5 = inverse of 5
    * @param _accrualPeriod the time it takes for interest to accrue in seconds
    * @return the id it just created
     */
    function configureNew(
    address,
    address,
    uint256, 
    uint256, 
    uint256, 
    uint256, 
    uint256 
    )
    external
    returns(uint256);
    
    /*
    * @notice function handles the payment of the loan. Does not have to be borrower
    *as payment comes in. The contract holds it until collection by bond owners. MUST APPROVE FIRST in ERC20 contract first
    * @param _id to pay off
    * @param _erc20Ammount is ammount in loan's ERC20 to pay
     */
    function payment(uint256, uint256) external;
    
    /*
    * @notice MUST approve this contract to spend your ERC1155s in bonds. Used to have this auto handled by the on received function.
    * However that was not a good idea as a hacker could create fake bonds.
    * @param _id is the id of the bond to send in
    * @param _amm is the ammount to send
     */
    function withdrawl(uint256, uint256) external;
    
    /*
    * @notice helper function
    * @param _id of loan to check
    * @return return if the contract is payed off or not as bool
     */
    function isComplete(uint256) external view returns(bool);
    /*
    * @notice Returns the ID for a loan given the borrower and index in the array
    * @param _borrower is borrower
    * @param _index is the index in the borrowers loan array
    * @return the loan ID
     */
    //
    function getId(address, uint256) external view returns(uint256);
}