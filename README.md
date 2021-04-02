LoanWolf Smart Contracts
========================

(for the Chainlink2021 Hackathon)

These are the V2 contracts for loanwolf decentralized non-colateralized lending. Unlike V1, the ERC20 payment contract standard here exists as an overridable template for issuing loans with payment in ERC20 tokens. There are 3 important contracts here. Bonds.sol, ERC20PaymentStandard.sol and ERC20CollateralStandard.sol. The depreciated SimpleEthPayment.sol is there as well. There is also a mock dai contract meant for testing as an erc20 token. There is no functionality, it only exists for testing. Truffle tets are in the tests folder. Migrations are not complete so don't just copy those over. Bellow are the descriptions of the functions for the relevant contracts.

Bonds.sol (v2)
==============

Introduction
------------
Bonds is an ERC-1155 token. And it inherits the code from [OpenZeppelin](https://docs.openzeppelin.com/contracts/3.x/api/token/erc1155)
Bonds are minted by borrowers. These bonds are ERC-1155s that can then be staked (to accrue interest).  

Functions
---------
`Constructor:`  
No params for contructor. However, the metadata URL required by ERC-1155 is hardcoded in the constructor. This should be changed.

`newLoan(address _paymentContractAddress, uint256 _id) external`  
newLoan will mint new bond ERC-1155s to the borrower as defined in a paymentContract who's address is passed as a parameter.
- the function calls the `issueBonds()` function of the payment contract with the ID and collects the returned address.
- that address must match the function caller (should be the borrower of the loan)
- the id is also saved in a mapping called idToContract to connec the id to the payment contract address.

`unstake(uint256 _index) external returns(bool)`  
unstake sends staked ERC-1155s back to their owner. The _index parameter is the pointer to the place in the linked list where this staking is done. The function also mints new ERC-1155s (of the same ID) as interest. When tokens are first staked the timestamp is noted. The difference between the unstake time and the stake time is then taken and divided by the "acruall period" from the payment contract. This is then multiplied by the ammount staked divided by the inverse interest rate. The result is a non-compounding simple interest. Walking through an example the staking process might look like this:  
1. Bob stakes 100 ERC-1155s which have an acruall period of 1 month and an inverse interest rate of 50 (2% monthly interest)
2. 3 months pass
3. Bob unstakes his ERC-1155s. And is given 106 back. As 3 Months * (100/50) = 6. That 6 is minted back along with his origionall 100.  
NOTE: tokens are MINTED back not transfered back. There was a strange issue with a contract not being approved to spend ERC-1155s that were in it's possesion. Would like to fix this. But it's a non breaking issue for now.  
  
A final note is the return value of unstakeAll(). This returns true if interest generation is successful. In a particular case it will not be. And that is when a paymentContract is marked as complete. Meaning a borrower has completed the "total payment due" as defined in the payment contract. If a contract is complete a staker will be returned a false flag and be only sent back his principal investment, no interest.

`getAccruances(address _who, uint256 _index) public view returns(uint256) `  
This function returns the number of passed accruance periods for a staker _who. Using the example of Bob above, if bob called this function just before unstaking he would have been returned 3 as 3 months passed and 1 month was the accruance period.
-NOTE: _who must be currently staking to call the function

Staking (Linked List)
---------------------
The `staking` mapping is a nested mapping containing a circular doubly linked list data structure that holds an address's staking info. Traversal of the linked list is to be done with the public mapping offchain. To traverse start at the HEAD (will always be 0) for a given user's address. Then look up the NEXT value for that user. Continue until you loop back to HEAD (0). Values are stored under the IOU struct named `value`. The IOU struct has the following values within it:  
- `bool staking;` true if currently staking
- `uint256 ID;` nft ID
- `uint256 ammount;` quantity staking 
- `uint256 timeStaked;` timestamp when staking started

The `unstake()` function makes use of the index in this linked list for deletions in constant time with low gas fees. Yaaaaaayyyy! When traversing the linked list and displaying to a user make sure to keep track of the "index" of each entry in the list. As if a user decides to unstake you will need to pass that index into the `unstake()` funciton.

ERC20PaymentStandard.sol
========================

Introduction
------------
The payment contract of a loan can be custom made and it's encouraged to be. But they all should be based off the ERC20PaymentStandard. That's not to say payment contracts must be ERC20 payment contracts but they must have functions like this so bonds can call them and interact with features of the contract. All the functions in this contract are virual so they can be overridden by any child contract. An example of a child contract will be bellow with the ERC20CollateralPayment contract.

Loans/Lookups
-------------

The contract holds 2 mappings. loanIDs and loanLookup. loanIDs maps each address to an array of loan IDs. The loanLookup returns a loan struct in response to a loanID. This is what a loan looks like:
- `bool issued;`
- `address ERC20Address;`
- `address borrower;`
- `uint256 paymentPeriod;`
- `uint256 paymentDueDate;`
- `uint256 minPayment;`
- `uint256 interestRateInverse;`
- `uint256 accrualPeriod;`
- `uint256 principal;`
- `uint256 totalPaymentsValue;`
- `uint256 awaitingCollection;`
- `uint256 paymentComplete;`

Functions (also this is the interface used by bonds.sol)
--------------------------------------------------------

`Constructor(address _bonds)`
The bonds contract address should go here

`getNumberOfLoans(address) external view returns(uint256)`
Simple enough. This returns the length of the loanIds array for address

`issueBonds(uint256) external returns(uint256,address);`
This function is called when new bond NFTs are minted. It should verify that the ID is not already issued and return the borrower address for confirmation that borrower is calling the function.

`addInterest(uint256, uint256) external returns(bool);`
This updates the `totalPaymentsValue` variable with new interest. Is called when a lender unstakes their loans in Bonds.sol

`getInterest(uint256) external view returns(uint256);`
This returns teh interestRateInverse for a loan. For Bonds.sol to use so it doesn't have to parse a struct

`isDelinquent(uint256) external view returns(bool);`
Returns true if the loan is delinquent. Can be overridden to return based off any kind of terms. But for now that term is "if minPayment is not made by paymentDueDate"

`configureNew(address, address, uint256, uint256, uint256, uint256, uint256)external;`
This function configures a new loan for a given borrower. ANYONE can configure a loan for anyone else. But only the borrower can mint the ERC-1155s and thus begin the loan. A lender can call this function with a borrowers name to give a sort of "loan request" the borrower can choose to accept by minting the ERC-1155s for it. The parameters are listed bellow:

- `_erc20` is the ERC20 contract address that will be used for payments
- `_borrower` is the borrower this loan is being configured for
- `_minPayment` is the minimum payment that must be made before the payment period ends
- `_paymentPeriod` payment must be made by this time or delinquent function will return true
- `_principal` the origional loan value before interest
- `_inverseInterestRate` the interest rate expressed as inverse. 2% = 1/5 = inverse of 5
- `_accrualPeriod` the time it takes for interest to accrue in seconds

`payment(uint256, uint256) external;`
This is the function that borrower calls to make their payments. IMPORTANT: You must approve the transfer with the designated ERC20 contract first.

`isComplete(uint256) external view returns(bool);`
Returns true if a loanID reflects a complete and paid off loan

`getId(address, uint256) external view;`
This function creates an ID for a loan. This is the hash of the address of a borrower, address of this address, and the index in the loanIDs array

Truffle Tests
-------------

Truffle tests can be run by running

`truffle test`

Testing is done with the Chai JS library and tests can be added under 

`test/loanwolf.test.js`

Feel free to add tests



