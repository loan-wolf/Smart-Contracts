Loan Wolf - Decentralized custom-collateralised lending
========================

We created Loan Wolf in order to build infrastructure for decentralized custom-collateralized lending. Currently in DeFi, in order to borrow on Aave or Compound, borrowers must lock at least 2x higher collateral than loan amount. Also, most of the collateral requirements are restricted to accepting ERC20 tokens. 

With zero Solidity knowledge, lenders create loan products that are configured by parameters like payment token type, duration, amount, APR, collateral token, collateral amount, liquidation parameters and required borrowers’ data for scoring. Interest rate is fully customizable and opens up options for variable interest loans. Possibility to issue wrapped token loans opens nearly 2T USD liquidity market! 

Borrowers select a loan product, fill in borrowers’ application and mint debt obligation (bond) ERC1155 token. Chainlink is used to pass Merkle Tree of hashed borrowers’ data to the blockchain for anonymous verification by independent lender validators. In the future, Chainlink infrastructure will also be used for decentralised credit scoring and validation.  

After loan application has been approved, borrowers can sell debt tokens to the lenders, and raise capital. With Loan Wolf, lenders can buy out even a part of or a fraction of a loan! Bonds can be resold partially or fully at the secondary market to other investors. Lenders must stake tokens for interest accrual. 
Upon repaying principal and interest of the loan, bond ERC1155 tokens are burned. 

Loan Wolf contracts provide infinite customization and modularity since each loan agreement is a separate entity of a smart contract. How about borrowing against your tokenized real estate, collectibles, or future subscription fees or even against another bond you own? You can do that with Loan Wolf. 

LoanWolf Architecture
========================

![Снимок экрана 2021-04-12 в 0 49 12](https://user-images.githubusercontent.com/1101279/114324177-1698a900-9b29-11eb-8877-bbabdbd554ab.png)

LoanWolf Smart Contracts
========================

![LW-SC-Arch-1](https://user-images.githubusercontent.com/1101279/114324196-2ca66980-9b29-11eb-894d-6896db63e45e.png)

![LW-SC-Arch-2](https://user-images.githubusercontent.com/1101279/114324203-30d28700-9b29-11eb-9582-ebfbc0e611e8.png)

ERC20 payment contract standard here exists as an overridable template for issuing loans with payment in ERC20 tokens. There are 3 important contracts here. Bonds.sol, ERC20PaymentStandard.sol and ERC20CollateralStandard.sol. The depreciated SimpleEthPayment.sol is there as well. There is also a mock DAI contract meant for testing as an erc20 token. There is no functionality, it only exists for testing. Truffle tets are in the tests folder. Migrations are not complete so don't just copy those over. Bellow are the descriptions of the functions for the relevant contracts.

NOTE: Contracts are now using Solc 0.6.6. That is because this commit includes Chainlink and the Chainlink client is not yet working with newer Solidity Compier versions. This has caused the need for some changes. Which will be expressed here.

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

`stake(uint256 _id, uint256 _amm) external`
This function sends your ERC1155s to the Bonds contract to stake. MUST approve bonds to spend your bonds before calling. It will add the staking to the linked list detailed bellow.  

Staking (Linked List)
---------------------
The `staking` mapping is a nested mapping containing a circular doubly linked list data structure that holds an address's staking info. Traversal of the linked list is to be done with the public mapping offchain. To traverse start at the HEAD (will always be 0) for a given user's address. Then look up the NEXT value for that user. Continue until you loop back to HEAD (0). Values are stored under the IOU struct named `value`. The IOU struct has the following values within it:  
- `uint256 ID;` nft ID
- `uint256 ammount;` quantity staking 
- `uint256 timeStaked;` timestamp when staking started

The `unstake()` function makes use of the index in this linked list for deletions in constant time with low gas fees. Yaaaaaayyyy! When traversing the linked list and displaying to a user make sure to keep track of the "index" of each entry in the list. As if a user decides to unstake you will need to pass that index into the `unstake()` funciton.

NOTE: Solc 0.6.x does not support returning user defined datatypes. So the `staking` mapping is not public and does not have a getter function. A new function was added:  
`getStakingAt(address _who, uint256 _index) external view returns(uint, uint, uint256, uint256, uint256)`  
This function returns all the info above as well as the last/next node pointers (the two uints)

ERC20PaymentStandard.sol
========================

Introduction
------------
The payment contract of a loan can be custom made and it's encouraged to be. But they all should be based off the ERC20PaymentStandard. That's not to say payment contracts must be ERC20 payment contracts but they must have functions like this so bonds can call them and interact with features of the contract. All the functions in this contract are virual so they can be overridden by any child contract. An example of a child contract will be bellow with the ERC20CollateralPayment contract.

NOTE: The payment standard uses chainlink. If you publish a custom payment contract and do not override the use of chainlink, you will need to fund the contract with LINK

Loans/Lookups
-------------

The contract holds 2 mappings. loanIDs and loanLookup. loanIDs maps each address to an array of loan IDs. The loanLookup returns a loan struct in response to a loanID. This is what a loan looks like:
- `bool issued;`
- `address ERC20Address;`
- `address borrower;`
- `bytes32 chainlinkRequestId;`
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
This returns the interestRateInverse for a loan. For Bonds.sol to use so it doesn't have to parse a struct

`isDelinquent(uint256) external view returns(bool);`
Returns true if the loan is delinquent. Can be overridden to return based off any kind of terms. But for now that term is "if minPayment is not made by paymentDueDate"

`configureNew(address, address, uint256, uint256, uint256, uint256, uint256)external returns(uint256);`
This function configures a new loan for a given borrower. ANYONE can configure a loan for anyone else. But only the borrower can mint the ERC-1155s and thus begin the loan. A lender can call this function with a borrowers name to give a sort of "loan request" the borrower can choose to accept by minting the ERC-1155s for it. The parameters are listed bellow:

- `_erc20` is the ERC20 contract address that will be used for payments
- `_borrower` is the borrower this loan is being configured for
- `_minPayment` is the minimum payment that must be made before the payment period ends
- `_paymentPeriod` payment must be made by this time or delinquent function will return true
- `_principal` the origional loan value before interest
- `_inverseInterestRate` the interest rate expressed as inverse. 2% = 1/5 = inverse of 5
- `_accrualPeriod` the time it takes for interest to accrue in seconds  
This function also uses chainlink to retreive the 

returns the id of the contract that was just created `chainlinkRequestId` for the loan. More on Chainlink bellow

`payment(uint256, uint256) external;`
This is the function that borrower calls to make their payments. IMPORTANT: You must approve the transfer with the designated ERC20 contract first.

`isComplete(uint256) external view returns(bool);`
Returns true if a loanID reflects a complete and paid off loan

`getId(address, uint256) external view;`
This function creates an ID for a loan. This is the hash of the address of a borrower, address of this address, and the index in the loanIDs array

`withdrawl(uint256, uint256) external`
This function is used to exchange ERC1155s as a lender for the ERC20s made as payments. 1 for 1. MUST approve in the Bonds contract before calling

Chainlink
---------
Chainlink oracles are called at the end of the `configureNew` function to the bellow API address for the purpose of getting a merkle root on chain.  
`http://40.121.211.35:5000/api/getloansdetails/:LOAN_ID`  
This is the LoanWolf API. Independant payment contract creators are welcome to replace with a different API. But it must have the functionality outlined bellow. But first, note, LOAN_ID is, as you may imagine, the loan ID calculated by the `getId` function. This means that upon loan application the backend must publish the merkleRoot to the coorseponding loanID before calling `configureNew`. This means the frontend (or server) must call getId and calculate the ID as well.  

Merkle roots
------------
The tree root is the backbone of LoanWolf. The merkle tree allows information about a loan to be provably verifyable to anyone, without revealing non-pertinant personal information, and it can do this all very efficiently. However, in order for this to work, a trusted public merkle root must be available. Luckily that's what smart contracts are all about. But we have to get the merkle root to the contract. So a backend must construct a merkle tree from the user's information and publish the root on a public API for the contract to access by Loan Id.  
This Loan ID must be expressed as a NUMBER. Even though it is a hash. You may be tempted to display it as a hex string but the Chainlink node will not read this string as hex. It has no job spec for base system. So it will read it as ASCII. And as I'm sure you can guess 0xabc.... is very different when read in hex than ascii. So the node will read it as a base 10 interger and then the smart contract will convert that to a Solidity bytes32 type. Since JS and many other languages do not support large 256 bit numbers the node have to read in number strings. So here's some handy code to turn your hex string in the common hash format to a string interger using the BN.js library:  
`let hashNum = new BN(MERKE_ROOT_AS_HEX_STRING, 16).toString();`  

Now the smart contract does NOT store the merkle root in the loan object since it takes time for the oracle to submit the value. Instead it holds a kind of pointer to the value as the Chainlink Request Id. This request id can be used to look up the merkle root in the public `merkleRoots` mapping. As the merkle root will be published there in bytes32 format once submitted by the node.

ERC20CollateralStandard.sol
===========================
This contract is an example of a custom implementation of the ERC20PaymentStandard. This child contract inherits everything from it's parent but adds the ability to post ERC20 collateral to a loan. It adds a collateralLookup mapping to store the ERC20 contract address and the ammount as collateral. It also overrides the ERC-1155 recieve function to handle collateral withdrawl if a loan is marked delinquent. If the loan is completed the borrower can withdrawl. NOTE: onERC1155BatchReceived is not implemented. Only single ERC1155 transfers handle collaterall colleciton. The new functions added are as follows:  

`addCollateral(address _ERC20Contract, uint256 _ammount, uint256 _loanId) external`
Only borrower can call this and add collateral at any point but can only add one kind of collateral. The ERC20 contract here does not have to be the same as the one in payment and can instead be anything. But if you choose to add more collateral it must be of the same ERC20 as the first one was. 

`returnCollateral(uint256 _loanId) external`
Function returns the collateral to the borrower if the loan is completed and borrower is calling.

Truffle Tests
-------------

Truffle tests can be run by running

`truffle test`

Testing is done with the Chai JS library and tests can be added under 

`test/loanwolf.test.js`

Feel free to add tests



