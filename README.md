LoanWolf Smart Contracts
========================

(for the Chainlink2021 Hackathon)
Imports are available both for Remix and local developement with the Openzeppelin npm package.

Bonds.sol
---------

Is an ERC-1155. Bonds are minted by borrowers with the ID as a interger representation of it's payment contract address. 
The payment contract is necessary to make a loan as it handles the details of payment, collection, interest and failure.

NOTE: as of right now, each loan needs it's own dedecated payment contract. In the future I'd like to have many people/loans use one contract

SimpleEthPayment.sol
--------------------

Example of a payment contract. Each loan in this system needs it's own payment contract that specifies (and enforces) the details of the loan. In the future I'd love to make the raw necesseties for this contract well documented so it's easier to create payment contracts
in accordance with the standard. At the very least have a simpleERCPayment as well.

Truffle Tests
-------------

Truffle tests can be run by running

`truffle test`

Testing is done with the Chai JS library and tests can be added under 

`test/loanwolf.test.js`

Feel free to add tests



