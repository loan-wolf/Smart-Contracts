/// SPDX-License-Identifier: None
pragma solidity ^0.6.6;

import "@openzeppelin/contracts/token/ERC1155/ERC1155Holder.sol";
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC1155} from '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import "@chainlink/contracts/src/v0.6/ChainlinkClient.sol";
/**
* @title ERC20PaymentStandard
* @author Carson Case
* @notice This contract is a standard meant to be overriden that works with the Bonds contract to offer noncolateralized, flexable lending onchain
 */
contract ERC20PaymentStandard is ERC1155Holder, ChainlinkClient{
    //Just Chainlink things
    address private oracle = 0x2f90A6D021db21e1B2A077c5a37B3C7E75D15b7e;
    bytes32 private jobId = "29fa9aa13bf1468788b7cc4a500a45b8";
    uint256 private fee = 0.1 * 10 ** 18; // 0.1 LINK

    // Initialized in constructor
    address public bondContract;
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
    mapping(uint256 => loan) public loanLookup;
    mapping(address => uint256[]) public loanIDs;
    mapping(bytes32 => bytes32) public merkleRoots;
    
    /**
    * @notice just sets bonds contract
    * @param _bonds contract
     */
    constructor(address _bonds) public{
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
    * @notice get the interest rate of a loan. Makes it easy for other contract since it doens't have to parse struct
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
    * @return the id it just created
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
            chainlinkRequestId: 0x0,
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
        //Make Chainlink Request for Merkle Root
        requestMerkleRoot(id);

        //For Truffle tests. Just skip Chainlink request. I don't have a local chainlink system
        //To mimic, just set chainlinkRequestId to hash of ID and merkle root to hash of "Hello World"
        // bytes32 reqID = keccak256(abi.encodePacked(id));
        // loanLookup[id].chainlinkRequestId = reqID;
        // merkleRoots[reqID] = keccak256("Hello World");
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
    
    /**
    * @notice MUST approve this contract to spend your ERC1155s in bonds. Used to have this auto handled by the on received function.
    * However that was not a good idea as a hacker could create fake bonds.
    * @param _id is the id of the bond to send in
    * @param _amm is the ammount to send
     */
    function withdrawl(uint256 _id, uint256 _amm) external virtual{
        IERC1155 bonds = IERC1155(bondContract);
        IERC20 erc20 = IERC20(loanLookup[_id].ERC20Address);
        require(loanLookup[_id].issued, "this loan has not been issued yet. How do you even have bonds for it???");
        require(_amm <= loanLookup[_id].awaitingCollection,"There are not enough payments available for collection");
        bonds.safeTransferFrom(msg.sender, address(this), _id, _amm, "");
        erc20.transfer(msg.sender, _amm);
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

    /**
    * @notice Chainlink Get Request function to request merkle Root from backend server
    * @param _id of loan
     */
    function requestMerkleRoot(uint256 _id) internal returns (bytes32 requestId) 
    {
        Chainlink.Request memory request = buildChainlinkRequest(jobId, address(this), this.fulfill.selector);
        request.add("get", "http://40.121.211.35:5000/api/getloansdetails");
        request.add("extPath",uint2str(_id));
        request.add("path", "merkleroot");
        // Sends the request
        bytes32 b = sendChainlinkRequestTo(oracle, request, fee);
        loanLookup[_id].chainlinkRequestId = b;
        return b;
    }

    /**
    * @notice Chainlink fulfill function. Called to set the merkle root for a request ID
    * @param _requestId is the request ID
    * @param _merkleRoot is what's returned
    */
    function fulfill(bytes32 _requestId, uint256 _merkleRoot) public recordChainlinkFulfillment(_requestId)
    {
        merkleRoots[_requestId] = bytes32(_merkleRoot);
    }

    /**
    * @notice this was stolen from Stackoverflow post:
    * https://stackoverflow.com/questions/47129173/how-to-convert-uint-to-string-in-solidity
    * Big thanks to Barnabas Ujvari
    * Just converts an int into a string
    * @param _i as the uint to turn to string
     */
    function uint2str(uint256 _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}