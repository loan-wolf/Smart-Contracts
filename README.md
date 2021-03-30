LoanWolf Smart Contracts
========================

(for the Chainlink2021 Hackathon)
Imports are available both for Remix and local developement with the Openzeppelin npm package.
These are the v1 contracts which only support single users of payment contracts. V2 will support multiple users for 
each payment contract.  
On Remix increase gas limit for Bonds.sol.

Bonds.sol v2
------------

Bonds is an ERC-1155 token. And it inherits the code from [OpenZeppelin](https://docs.openzeppelin.com/contracts/3.x/api/token/erc1155)
Bonds are minted by borrowers with the ID as a interger representation of it's payment contract address. 
The payment contract is necessary to make a loan as it handles the details of payment, collection, interest and failure.

`Constructor:`  
No params for contructor. However, the metadata URL required by ERC-1155 is hardcoded in the constructor

The following functions are unique to Bonds and callable externally:

`newLoan(address _paymentContractAddress) external returns(uint256)`  
newLoan will mint new bond ERC-1155s to the borrower as defined in a paymentContract who's address is passed as a parameter.
- the caller of the newLoan function must be the borrower defined in the payment contract.
- the payment contract must be "complete". Meaning there is no current loan outstanding on the contract
- the function returns a uint256 representation of the payment contract's address which is also the ERC-1155's ID

`stake(uint256 _id, uint256 _amm) external`  
Stake deposits a lenders ERC-1155's in order to earn interest in accordance to the interest defined in the token's payment contract.
In the future I'd like to depreciate this in favor of having this automatically handled with ERC-1155's sent to the contract.  
- CAN now stake multiple times. New entries are added to a circular doubly linked list and can be accessed throug the staking mapping
- Must use the setApprovalAll function to allow Bonds to send your ERC-1155's before calling
- _id is the ID of the ERC-1155
- _amm is the ammount to sent. This cannot be more than your balance.
Staking mechanics will be explained more in the unstake function's description

`unstake(uint256 _index) external returns(bool)`  
unstake sends staked ERC-1155s back to their owner. The _index parameter is the pointer to the place in the linked list where this staking is done. More on that bellow. The function also mints new ERC-1155s (of the same ID) as interest. When tokens are first staked the timestamp is noted. The difference between the unstake time and the stake time is then taken and divided by the "acruall period" from the payment contract. This is then multiplied by the ammount staked divided by the inverse interest rate. The result is a non-compounding simple interest. Walking through an example the staking process might look like this:  
1. Bob stakes 100 ERC-1155s which have an acruall period of 1 month and an inverse interest rate of 50 (2% monthly interest)
2. 3 months pass
3. Bob unstakes his ERC-1155s. And is given 106 back. As 3 Months * (100/50) = 6. That 6 is minted back along with his origionall 100.  
NOTE: tokens are MINTED back not transfered back. There was a strange issue with a contract not being approved to spend ERC-1155s that were in it's possesion. Would like to fix this in V2. But it's a non breaking issue for now.  
  
A final note is the return value of unstakeAll(). This returns true if interest generation is successful. In a particular case it will not be. And that is when a paymentContract is marked as complete. Meaning a borrower has completed the "total payment due" as defined in the payment contract. If a contract is complete a staker will be returned a false flag and be only sent back his principal investment, no interest.

`getAccruances(address _who) public view returns(uint256)`  
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

paymentContract interface in Bonds.sol
--------------------------------------
If you are interest in creating your own payment contract. Understand it must include the following functions in order to be compatable with Bonds.sol:  
The following are get functions (auto generated by Solidity Compilers) for public state variables. Just have these state variables in the contract  
`principal() external view returns(uint256);`  
`accrualPeriod() external view returns(uint256);`  
`interestRateInverse() external view returns(uint256);`  
`borrower() external view returns(address);` 
`issued() external view returns(bool);`   
The following are real functions that must do certain things:  
`addInterest(uint256 _amm) external returns(bool);`  
Function must update the payment contract with new interest generated and return true if successful.  
`isComplete() external returns(bool);`  
must return true if the loan is paid off or bonds are not issued.
`issueBonds() external;`  
must flag the "issued" variable above as true to show bonds have been minted for the loan.  

SimpleEthPayment.sol v1
-----------------------

Example of a payment contract. Each loan in this system needs it's own payment contract that specifies (and enforces) the details of the loan. Please note that this v1 implementation is lacking in a lot of functionality. These are aimed to be solved in v2, the biggest of which is that a payment contract like SimpleEthPayment must be deployed for (and before) each loan is started by calling `newLoan()` in Bonds.sol. Also, the public state variables of the contract must be configured in the constructor and cannot be changed after deployment. However, these payment contracts can be created by anyone using LoanWolf and loan payments are by no means limited to the contracts developed durring this hackathon. Any contract that implements the interface functions above can be used with the protocol.  

Public State Variables:
`bool public issued;`  
`address public bondContract;`  
`address public borrower;`  
`uint256 public paymentPeriod;`  
`uint256 public paymentDueDate;`  
`uint256 public minPayment;`  
`uint256 public interestRateInverse;`  
`uint256 public accrualPeriod;`  
`uint256 public principal;`  
`uint256 public totalPaymentsValue;`  
This starts as principal but increased with interest added
`uint256 public awaitingCollection;`  
`uint256 public paymentComplete;`  

The constructor takes the following as parameters to configure the contract  
`_bondContract` is the bond contract address  
`_minPayment` is the minimum payment that must be made before the payment period ends  
`_paymentPeriod` payment must be made by this time or delinquent function will return true  
`_principal` the origional loan value before interest  
`_inverseInterestRate` the interest rate expressed as inverse. 2% = 1/5 = inverse of 5  
`_accrualPeriod` the time it takes for interest to accrue in seconds  

The following functions are implemented:
`payment() payable external incomplete`  
send a payment to this function in eth and it will reset the paymentDueDate as current time plus the payment period.
- contract must be incomplete, meaning in progress
- payment must also meet the minimum payment defined but there's an exception for the last payment which may be less than the minimum payment  

`collect(uint256 _amm) external`  
Send matching ERC-1155s from Bonds from a bond owner to the contract and return an equal ammount of eth.
- must approve simpleEthPayment in bonds first with `setApprovalForAll()`
- _amm must not be more than the awaiting collection ammount
- collector must have at least _amm ERC-1155s with the ID matching the simpleEthPayment contract's address  

`isDelinquent() external view returns(bool)`  
Returns true if the current time surpasses the payment due date  
Reminder that this date updates upon payments  

`addInterest(uint256 _amm) onlyBonds external returns(bool)`  
This function may only be called by the Bonds contract. It updates the total ammount due to reflect interest collected by stakers  

`isComplete() public view returns(bool)`  
Returns true if the payment complete and total payment value is equal. Meaning loan is paid off or bonds are not yet issued.

Truffle Tests
-------------

Truffle tests can be run by running

`truffle test`

Testing is done with the Chai JS library and tests can be added under 

`test/loanwolf.test.js`

Feel free to add tests



