/// SPDX-License-Identifier: None
pragma solidity ^0.8.0;

/**
* @title IERC20PaymentStandard
* @author Carson Case
 */
interface IERC20PaymentStandard{
    struct loan {
        bool issued;
        address ERC20Address;
        address borrower;
        bytes32 merkleRoot;
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

    
    function getNumberOfLoans(address) external view returns(uint256);
    
    function issueBonds(uint256) external returns(uint256,address);
    
    function addInterest(uint256, uint256) external returns(bool);

    function getInterest(uint256) external view returns(uint256);
    
    function isDelinquent(uint256) external view returns(bool);
    
    function configureNew(address, uint256, uint256, uint256, uint256, uint256)external;
    
    function payment(uint256, uint256) external ;
    
    function isComplete(uint256) external view returns(bool);

    function getId(address, uint256) external view;

    function withdrawl(uint256, uint256) external;
}