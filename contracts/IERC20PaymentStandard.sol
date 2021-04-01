/// SPDX-License-Identifier: None
pragma solidity ^0.8.0;

/**
* @title IERC20PaymentStandard
* @author Carson Case
 */
interface IERC20PaymentStandard{
    
    
    function getNumberOfLoans(address) external view returns(uint256);
    
    function issueBonds(uint256) external returns(uint256,address);
    
    function addInterest(uint256, uint256) external returns(bool);

    function getInterest(uint256) external view returns(uint256);
    
    function isDelinquent(uint256) external view returns(bool);
    
    function configureNew(address, uint256, uint256, uint256, uint256, uint256)external;
    
    function payment(uint256, uint256) external ;
    
    function isComplete(uint256) external view returns(bool);

    function getId(address, uint256) external view;
}