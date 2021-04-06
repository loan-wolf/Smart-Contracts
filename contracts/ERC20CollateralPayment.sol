/// SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "./ERC20PaymentStandard.sol";
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/**
* @title ERC20CollateralPayment
* @author Carson Case
* @notice this is an example of a override of ERC20PaymentStandard. This offers ERC20 collateral to be be added
 */
contract ERC20CollateralPayment is ERC20PaymentStandard{
    /// @notice collateral info is stored in a struct/mapping pair
    struct collateral{
        address ERC20Contract;
        uint256 ammount;
    }
    mapping(uint256 => collateral) public collateralLookup;

    /**
    * @notice constructor just runs the ERC20PaymentStandard constructor
    * @param _bonds is the contract address of bonds
     */
    constructor(address _bonds) ERC20PaymentStandard(_bonds){}

    /**
    * @notice addCollateral must be called before issuing loan
    * @param _ERC20Contract address of the ERC20 you want to have as collaterall. DOES NOT have to be equal to payment ERC20
    * @param _ammount is the ammount to add as collateral
    * @param _loanId is the loan ID to add collateral to
     */
    function addCollateral(address _ERC20Contract, uint256 _ammount, uint256 _loanId) external{
        require(loanLookup[_loanId].borrower == msg.sender, "only the borrower can add collateral");
        IERC20 erc20 = IERC20(_ERC20Contract);
        if(collateralLookup[_loanId].ammount == 0){
            collateralLookup[_loanId] = collateral(_ERC20Contract, _ammount);
        }else{
            require(_ERC20Contract == collateralLookup[_loanId].ERC20Contract, "When increasing collateral, you must use the same ERC20 address ");
            collateralLookup[_loanId].ammount += _ammount;
        }
        erc20.transferFrom(msg.sender, address(this), _ammount);
    }

    /**
    * @notice return Collateral when the loan is complete 
    * @param _loanId is the loan ID
     */
    function returnCollateral(uint256 _loanId) external{
        require(msg.sender == loanLookup[_loanId].borrower, "only the borrower can collect collateral");
        require(isComplete(_loanId) || !loanLookup[_loanId].issued, "loan must be paid off or not started to collect collateral");
        IERC20 erc20 = IERC20(collateralLookup[_loanId].ERC20Contract);
        erc20.transfer(msg.sender, collateralLookup[_loanId].ammount);
    }

    /**
    * @notice MUST approve this contract to spend your ERC1155s in bonds. Used to have this auto handled by the on received function.
    * However that was not a good idea as a hacker could create fake bonds.
    * @param _id is the id of the bond to send in
    * @param _amm is the ammount to send
     */
    function withdrawl(uint256 _id, uint256 _amm) external override{
        IERC1155 erc1155 = IERC1155(bondContract);
        IERC20 erc20 = IERC20(loanLookup[_id].ERC20Address);
        IERC20 col = IERC20(collateralLookup[_id].ERC20Contract);
        require(loanLookup[_id].issued, "this loan has not been issued yet. How do you even have bonds for it???");
        erc1155.safeTransferFrom(msg.sender, address(this), _id, _amm, "");
        //if loan is delinquent and there's collateral to collect
        if(isDelinquent(_id) && collateralLookup[_id].ammount !=0){
            //determine if we should send remainder of collateral or exact ammount of bonds sent
            if(collateralLookup[_id].ammount < _amm){
                collateralLookup[_id].ammount = 0;
                col.transfer(msg.sender, collateralLookup[_id].ammount);
            }else{
                collateralLookup[_id].ammount -= _amm;
                col.transfer(msg.sender, _amm);
            }
        }else{
            if(_amm > loanLookup[_id].awaitingCollection){
                revert("The ammount your are trying to collect is not available. And/Or there is no collateral to collect");
            }
        }
        //if there's payments to collect in this ammount, collect them.
        if(_amm <= loanLookup[_id].awaitingCollection){
            erc20.transfer(msg.sender, _amm);
        }

    }
}